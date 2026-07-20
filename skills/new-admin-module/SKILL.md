---
name: new-admin-module
description: Scaffolds a new CRUD module following your codebase's documented module pattern (schema → migration → repository → service → handler → module registration), wires it into the server, and publishes its interface to the shared resolver layer if other modules consume it. Use when adding a new feature area to your admin/API service.
---

# Add a new CRUD module

> **This skill is a TEMPLATE.** It encodes an opinionated 6-layer module pattern that many service codebases follow. After `/init`, specialize it for your org: document your codebase's concrete module pattern — file names, ORM, framework, tenancy middleware, canonical example module — in `.aif/context/conventions.md`, and rewrite the placeholder sections below to point at real paths and types. The layer sequence (schema → migration → repository → service → handler → module registration) and the invariants (tenancy filters everywhere, soft deletes, no cross-module imports) survive specialization unchanged.

## Overview

Modular service codebases are structured as many self-contained modules under a single module directory (e.g. `internal/<service>/module/<name>/`). Most follow a 6-layer pattern; modules without DB tables skip the migration/repository layers. This skill scaffolds a new module correctly, with multi-tenancy, soft-deletes, API docs, and cross-module wiring intact.

The examples below are Go-flavored for concreteness — substitute your stack's equivalents; the layers and invariants are what matter.

## When to use

- Adding a new feature area to your admin/API service (new CRUD resource, new internal service proxy, new platform primitive)
- The work touches the database, the ORM layer, and the versioned API surface

**Don't use** for:

- Small additions to an existing module (a new endpoint, a new field) → just edit
- Cross-service work that doesn't add a module → use the `cross-repo-impact` agent first
- Changes owned by another repo (e.g. a shared policy or schema repo) → work there directly

If this introduces a new platform-level promise (a new API surface external integrators rely on), run `/feature-prep` FIRST — if your org keeps a spec registry (config key `org.spec_registry`), it may need an entry before code lands.

## Before starting, confirm

1. **Module name** (snake_case, e.g. `quota`, `billing`, `usage_metering`) — maps to the module directory
2. **Primary resource name** (CamelCase, e.g. `Order`, `QuotaDefinition`) — used in type names
3. **Table name(s)** (plural snake_case, e.g. `orders`, `quotas`) — for migrations
4. **Does the module need DB tables?** If no (e.g. it's a thin proxy to an external service), skip the migration + repository layers; say so when scaffolding
5. **Cross-module dependencies?** If yes, depend via the shared resolver layer (a `base/`-style package of getter/setter indirections), never via direct imports between modules
6. **Does this module export functionality to other modules?** If yes, you'll add a resolver in the shared layer and publish the service to it from server startup

Before writing code, **read `~/.claude/aif-references/multi-tenancy-checklist.md`** — every query in this skill must satisfy it. The tenant-scoping keys come from `tenancy.keys` in `.aif/config.yml` (examples below use `account_id` + `project_id`); if `tenancy.keys` is absent, ask the user whether the service is multi-tenant before scaffolding queries.

## The 6-layer pattern

Every module with DB tables has these layers (one file each is typical):

| Layer / file   | Purpose                                                                                                                                          |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `schema.go`    | ORM models, enums, helpers                                                                                                                       |
| `migration.go` | Idempotent SQL `CREATE TABLE IF NOT EXISTS` (declarative; runs from the repository's startup hook)                                              |
| `repo.go`      | Atomic DB operations + a startup hook that runs the migrations                                                                                   |
| `service.go`   | Business logic — orchestrates repository calls, calls other modules via the shared resolvers                                                     |
| `handler.go`   | HTTP handlers, route registration, API-doc annotations, request validation                                                                       |
| `module.go`    | Wiring — instantiates repo/service/handler, exposes a register-handlers entrypoint, exposes a getter for the service so the server can publish it |

**Pattern variations** (look at neighboring modules to match):

- Proxy modules (no DB tables) skip `migration.go` + `repo.go`
- Some modules embed migrations directly in `repo.go` — match whichever variant your codebase's canonical example uses

Reference: pick your codebase's canonical 6-layer module (record it in `.aif/context/conventions.md`) and mirror it throughout. Everything below assumes you have that precedent open.

## Process

### 1. Create the directory and files

```sh
cd <module-root>
mkdir -p <module_name>
cd <module_name>
touch schema.go migration.go repo.go service.go handler.go module.go
```

### 2. `schema.go` — models and constants

ORM models. Required fields:

- A UUID primary key with a server-side default
- Every key in `tenancy.keys` as a NOT NULL column (e.g. `AccountID`, `ProjectID`)
- `CreatedAt`, `UpdatedAt`, and `IsActive bool` (default true) for soft deletes

```go
package orders

type Order struct {
    ID         uuid.UUID `db:"id,pk,default:gen_random_uuid()"`
    AccountID  string    `db:"account_id,notnull"`
    ProjectID  uuid.UUID `db:"project_id,notnull"`

    Name       string    `db:"name,notnull"`
    IsActive   bool      `db:"is_active,notnull,default:true"`

    CreatedAt  time.Time `db:"created_at,notnull,default:now()"`
    UpdatedAt  time.Time `db:"updated_at,notnull,default:now()"`
    CreatedBy  string    `db:"created_by"`
}
```

(Use your ORM's actual tags/base-model conventions — copy from the precedent module.)

### 3. `migration.go` — raw SQL + a RunMigrations entrypoint

```sql
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id TEXT NOT NULL,
    project_id UUID NOT NULL,
    name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by TEXT
);

CREATE INDEX IF NOT EXISTS idx_orders_account_project
    ON orders (account_id, project_id)
    WHERE is_active;
```

Migration safety: `CREATE ... IF NOT EXISTS` throughout, partial indexes on `WHERE is_active`, and multi-tenant indexes start with the tenancy keys (`(account_id, project_id, ...)`). For non-trivial migrations, run the `migration-analyzer` agent and read `~/.claude/aif-references/migration-safety-checklist.md`.

### 4. `repo.go` — atomic DB ops with a startup migration hook

**Every read and write filters on ALL keys in `tenancy.keys`.** No exceptions.

```go
package orders

func NewRepository(db *DB) (*Repository, error) {
    repo := &Repository{db: db}
    if err := repo.OnStart(context.Background()); err != nil {
        return nil, err
    }
    return repo, nil
}

func (r *Repository) OnStart(ctx context.Context) error {
    return RunMigrations(ctx, r.db)
}

func (r *Repository) GetByID(ctx context.Context, id uuid.UUID, accountID string, projectID uuid.UUID) (*Order, error) {
    // SELECT ... WHERE id = ? AND account_id = ? AND project_id = ? AND is_active
}

func (r *Repository) SoftDelete(ctx context.Context, id uuid.UUID, accountID string, projectID uuid.UUID) error {
    // UPDATE ... SET is_active = false, updated_at = now()
    // WHERE id = ? AND account_id = ? AND project_id = ?
}
```

If your codebase has no centralized migration runner, the repository's startup hook is where migrations run — confirm against the precedent module.

### 5. `service.go` — business logic

- Orchestrates repository calls
- Calls other modules via the shared resolver layer (never direct imports)
- Enforces quota and permissions
- Emits audit events if applicable

```go
func (s *Service) CreateOrder(ctx context.Context, req *CreateOrderRequest) (*Order, error) {
    if checker := base.GetQuotaChecker(); checker != nil {
        if err := checker.EnforceQuota(ctx, req.AccountID, "orders", 1); err != nil {
            return nil, err
        }
    }
    // business validation here, then s.repo.Create(...)
}
```

Match the actual signature of the resolver method when you call it — copy from a real call site in a neighboring module rather than guessing.

### 6. `handler.go` — HTTP layer

Derive the tenancy identifiers from the **request context** (set by your tenant middleware), not from headers, body, or the JWT directly. See `~/.claude/aif-references/jwt-checklist.md`.

```go
func (h *Handler) Register(r *RouterGroup) {
    r.POST("/order", h.CreateOrder)
    r.GET("/orders", h.ListOrders)
    r.GET("/order/:id", h.GetOrder)
    r.PUT("/order/:id", h.UpdateOrder)
    r.DELETE("/order/:id", h.DeleteOrder)
}

func (h *Handler) CreateOrder(c *Context) {
    ctx := c.Request.Context()

    accountID := model.GetAccountIDFromContext(ctx)   // set by tenant middleware
    projectID := model.GetProjectIDFromContext(ctx)   // set by tenant middleware

    // bind + validate request, stamp tenancy keys, call the service
}
```

Your tenant middleware parses the auth token once and stores the tenancy identifiers in the request context; handlers read them via the context accessors. **Never extract claims yourself in the handler.** Add API-doc annotations (swagger/OpenAPI) per your codebase's convention.

### 7. `module.go` — wiring

```go
func NewOrdersModule(db *DB) (*Module, error) {
    repo, err := NewRepository(db)   // migrations run here via the startup hook
    if err != nil {
        return nil, err
    }
    service := NewService(repo)
    handler := NewHandler(service)
    return &Module{Repo: repo, Service: service, Handler: handler}, nil
}

func (m *Module) GetService() *Service { return m.Service }   // for resolver wiring

func (m *Module) RegisterHandlers(engine *Engine, cfg *Config) {
    v1 := engine.Group("/v1/admin")
    m.Handler.Register(v1)
}
```

The register-handlers shape is what the server expects when it iterates over modules. The service getter exposes the service so server startup can publish it to the shared resolver layer if other modules will call it.

### 8. Wire into the server's startup

Find the server startup file (search for where the precedent module is constructed) and mirror its wiring:

```go
ordersModule, err := orders.NewOrdersModule(db)
if err != nil {
    return fmt.Errorf("failed to initialize orders module: %w", err)
}
s.modules = append(s.modules, ordersModule)

// If other modules need to call into this one:
base.SetOrdersChecker(ordersModule.GetService())
```

Module routes get registered later in the same function via the modules loop — you don't add a per-module register call; the existing loop does it for you.

### 9. If exporting to other modules, add a shared resolver

One file in the shared resolver package, mirroring the precedent:

```go
// module/base/orders.go
package base

type OrdersChecker interface {
    IsOrderActive(ctx context.Context, id uuid.UUID) (bool, error)
}

var (
    globalOrdersChecker OrdersChecker
    ordersMu            sync.RWMutex
)

func SetOrdersChecker(c OrdersChecker) { /* write-locked set */ }
func GetOrdersChecker() OrdersChecker  { /* read-locked get */ }
```

Server startup calls the setter. Other modules pull on demand: `if c := base.GetOrdersChecker(); c != nil { ... }`. **Always nil-check** — the resolver may not be wired during partial startup or in tests.

### 10. Regenerate API docs

Run your codebase's API-doc generation (e.g. `make swagger`) and commit the regenerated files. Skip and say so if the codebase has no doc generation.

### 11. Build, test, lint

Run the repo's standard build/test/lint targets (e.g. `make build && make test && make lint`).

### 12. Run cross-repo-impact

> _"Have cross-repo-impact check what else needs to change now that I've added the `<module-name>` module. Specifically: frontend clients, SDK wrappers, ingestion pipelines."_

Scope it to the sibling repos declared under `repos:` in `.aif/config.yml`; if there are none, skip and say so.

### 13. Verify in the shared dev environment after deploy

After merge and deploy to your shared dev environment (`environments.dev.name`):

- If an MCP server is configured (`mcp.namespace`), use its `mcp__<namespace>__*` tools to confirm: the table exists with expected columns/indexes, a trivial query works, pods rolled out cleanly, no migration errors at boot (a missing migration log line means the repository wiring is wrong), and no error-rate spike on the new endpoints.
- If no MCP server is configured, say so and use local alternatives: the `environments.dev.observability` sequence from config, `kubectl` if available, or a direct DB connection — never fabricate live state.
- If `environments.dev` is absent, skip this step and tell the user.

### 14. Commit

Single PR: 6 files (or 4 for no-DB modules), server wiring, doc regen, shared resolver if applicable, cross-repo follow-ups. Subject: `feat: add <module> module` — must match `org.commit_prefix_regex` (conventional commits if absent).

## Rationalizations (and rebuttals)

| You'll be tempted to think…                                                    | Why it's wrong                                                                                                              |
| ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------|
| "I'll skip the tenancy filters in this query — it's an internal lookup"        | Multi-tenancy break. Admin endpoints serve specific tenants; there is no "internal lookup". Filter on every `tenancy.keys` key. |
| "The handler can take the tenant ID from the body for this admin-only endpoint" | A tampered body would let a user read another tenant's data. Always the request context (set by tenant middleware), never body. |
| "Hard DELETE is fine — it's not user-facing"                                   | Soft-delete is an invariant. Audit, restore, FK safety all depend on it. Use `is_active = false`.                           |
| "I'll import the other module directly to avoid the resolver dance"            | Direct cross-module imports become circular within months. Use the shared resolver layer — that's why it exists.            |
| "I'll skip the migration; the column already exists in the dev environment"    | Migrations are idempotent (`IF NOT EXISTS`). Adding it to the migration is what guarantees staging/prod parity.             |
| "I'll put validation in `handler.go` since it's just request shape"            | Request shape (binding tags) goes in the DTO. Business validation (rules parse, quota allows) goes in `service.go`.         |
| "I'll skip doc regeneration; CI regen is enough"                               | CI is a check, not a producer. Commit the regenerated docs.                                                                 |
| "I remember a claims helper from another module — I'll just call it"           | Don't guess helper names. Copy the context accessors from a real handler in the precedent module.                           |

## Red flags

- A query in `repo.go` missing a `WHERE` clause for any key in `tenancy.keys`. Stop, add them.
- A handler reading a tenant ID from a path param or a request header. Forbidden.
- A direct import of another module's package in your `service.go`. Use the shared resolvers.
- A SQL migration that lacks `IF NOT EXISTS`. Not idempotent — fix.
- An `is_active` filter missing on a read. Soft-deleted rows will leak through.
- Business logic in `repo.go` (e.g. quota checks). Belongs in `service.go`.
- A migration method invented on the module struct. Migrations run from the repository's startup hook — match the precedent.
- Server wiring calling the module's route registration directly. Append to the modules list and let the existing loop call it.

## Verification

Done when:

- [ ] All 6 files (or 4 for no-DB modules) exist; the shared resolver file exists if applicable
- [ ] Build, test, and lint pass in the service repo
- [ ] API-doc regeneration produces a non-empty diff that's committed (if the codebase generates docs)
- [ ] Every query in `repo.go` filters on every key in `tenancy.keys`
- [ ] The handler derives tenancy identifiers from the request-context accessors; never from body/header
- [ ] Server startup appends the module to the modules list and (if exporting) publishes the service to the shared resolver
- [ ] After deploy: the new table exists in the shared dev environment (via `mcp__<namespace>__*` tools or stated local alternatives)
- [ ] Pod logs show a clean migration at boot; no boot errors
- [ ] No error-rate or latency regression on the new endpoints
- [ ] The cross-repo-impact agent has surfaced any frontend/SDK follow-ups

## Anti-patterns

- ❌ Tenancy identifiers from headers or request body
- ❌ Direct imports between modules (use the shared resolver layer)
- ❌ Business logic in `handler.go` or `repo.go`
- ❌ SQL queries without WHERE clauses for every `tenancy.keys` key
- ❌ Hard DELETE — use soft delete via `is_active = false`
- ❌ Missing `is_active` filter on reads
- ❌ Inventing a migration method that doesn't fit the codebase pattern
- ❌ Skipping API-doc regeneration
- ❌ Guessing helper/accessor names instead of copying from the precedent module
