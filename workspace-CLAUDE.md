<!--
  ═══════════════════════════════════════════════════════════════════════════
  WORKSPACE CLAUDE.md — FILL-IN TEMPLATE
  ═══════════════════════════════════════════════════════════════════════════

  This file is your org's "platform bible." install.sh symlinks it to
  <workspace>/CLAUDE.md, and Claude Code reads CLAUDE.md from every parent
  directory — so EVERYTHING in this file loads into EVERY session in EVERY
  repo under your workspace. That is both its power and its cost.

  The rule for what belongs here: only content that is (a) true across all
  repos and (b) needed often enough that loading it every session beats
  looking it up. Each section below earns its always-loaded cost like this:

  - Service Map ............ Claude's mental model of your platform. Without
                             it, every cross-repo question starts with 20
                             file reads. One table replaces all of that.
  - Config Repo layout ..... Where deployment/config truth lives. Prevents
                             Claude editing generated or wrong-layer config.
  - Local Dev (setup +     The commands Claude runs dozens of times per
    daily commands) ........ session. Wrong guesses here are the #1 source
                             of wasted turns.
  - Per-Repo Build ......... Lets Claude verify its own work (build/test/
                             lint) without asking you how.
  - Auth Contract .......... The thing Claude must NEVER get wrong. Token
                             types, who trusts whom, headers. Security bugs
                             start where this is fuzzy.
  - Multi-Tenancy .......... Your tenant-isolation invariant, stated once,
                             enforced everywhere. Keep in sync with
                             `tenancy.keys` in .aif/config.yml.
  - Cross-Repo Data Flow ... Which service calls which. Turns "where does
                             this request go next?" into a lookup.
  - Database Conventions ... ORM, migrations, ID scheme, soft deletes.
                             Prevents convention drift in generated code.
  - CI/CD + Commit ......... What makes CI reject a commit or PR. Claude
                             commits constantly; this must be exact.
  - Working with Claude    Documents the ai-factory toolkit itself (agents,
    Code (KEEP) ............ skills, references, hooks). Mostly org-neutral —
                             fill in the few <placeholders>, keep the rest.

  HOW TO FILL THIS IN:
  1. Replace every <angle-bracket placeholder> with your org's real value.
  2. Replace the example rows (api, web, worker) with your real repos.
  3. Delete sections that don't apply (e.g. Multi-Tenancy if single-tenant) —
     an absent section is better than a speculative one.
  4. Keep it lean. If a section grows past ~80 lines, move detail into a
     per-repo CLAUDE.md or a reference doc and link to it.
  5. Where a value also lives in `.aif/config.yml` (commit regex, tenancy
     keys, local-stack commands, regression repo), this file is the
     human-readable copy — keep the two in sync; the config is what skills
     and agents read programmatically.
  6. Delete this comment block when you're done.
  ═══════════════════════════════════════════════════════════════════════════
-->

# <Your Org> Platform — Workspace Context

> **`ai-factory/install.sh` symlinks this file to `<workspace>/CLAUDE.md`** —
> the workspace root resolves as `AIF_WORKSPACE` env → machine config
> (`~/.claude/aif/config.yml` `workspace.root`) → the toolkit clone's parent
> directory. If a real (non-symlink) CLAUDE.md already exists there,
> install.sh skips it with a warning. Claude Code reads CLAUDE.md from
> every parent directory, so this file loads automatically in every repo
> session — no per-session setup needed.

---

## Service Map

<!-- One row per repo. Keep the Role column dense — it's Claude's index of
     your platform. Replace these three example rows with your real repos. -->

| Repo     | Language       | Role                                                        | Local Port |
| -------- | -------------- | ----------------------------------------------------------- | ---------- |
| `api`    | <Go/Gin>       | Primary API — <modules/domains it owns>                     | <8040>     |
| `web`    | <Next.js>      | Web dashboard — <which products/pages it serves>            | <3000>     |
| `worker` | <Python>       | Async job execution — <queues/pipelines it consumes>        | <8050>     |

**Infrastructure (local docker):** <e.g. `db` (PostgreSQL + extensions), `redis`, `<analytics-store>`, `<feature-flag-service>`, `<reverse-proxy>`>

---

## <config-repo> — The Config Repo

<!-- If one repo owns deployment config (compose files, Helm values,
     ConfigMaps, feature flags), document its layers here so Claude edits
     the right one. If config lives per-repo instead, replace this section
     with a note saying so. -->

Everything deployment-related lives here. Distinct config layers:

### 1. Local Dev — `<config-repo>/<local-deploy-dir>/`

The only place you work for local development. (Keep this path in sync with
`local_stack.dir` in `.aif/config.yml`.)

```
<config-repo>/<local-deploy-dir>/
├── <Makefile or equivalent>          ← ALL local dev commands (run from this dir)
├── <docker-compose.yaml or Tiltfile> ← All services wired together
└── configs/
    ├── <env file>                    ← ⚠️  SECRET — your local env vars (gitignored)
    ├── <env file example>            ← Template — copy this to the real env file
    ├── api/
    │   └── config.yaml               ← Service config (non-secret)
    ├── web/
    │   └── <dotenv.env>              ← ⚠️  SECRET — frontend env vars (gitignored)
    └── worker/
        └── config.yaml
```

**The local env file** is the single source of secrets for all local services.
Document exactly how it's passed (e.g. `docker compose --env-file ...`).

### 2. Deployed App Config — `<config-repo>/<app-config-dir>/`

<!-- Per-service config deployed as ConfigMaps / parameter store / etc.
     Show the directory shape so Claude knows one dir per service. -->

Per-service `config.yaml` files deployed as <ConfigMaps / your mechanism>. One
directory per service.

### 3. Per-Environment Deploy Values — `<config-repo>/<deploy-dir>/`

<!-- Helm values, Terraform tfvars, CDK context — whatever varies by env. -->

```
<config-repo>/<deploy-dir>/
├── <dev-env>/                        ← Shared dev environment
│   └── ... (one file per service)
└── <prod-env>/                       ← Production
    └── ...
```

### 4. Feature Flags — `<config-repo>/<flags-dir>/`

<Your feature-flag system> config per environment.

---

## Local Dev — First-Time Setup

**All commands run from `<config-repo>/<local-deploy-dir>/`.**

### Prerequisites

Clone these repos as siblings under the same workspace root (keep this list in
sync with `repos:` in `.aif/config.yml`):

```
<workspace>/
├── <config-repo>/      ← must be here
├── api/
├── web/
└── worker/
```

### One-Time Setup

```bash
cd <workspace>/<config-repo>/<local-deploy-dir>

# 1. Copy and fill in secrets
cp configs/<env-file-example> configs/<env-file>
# Edit it — fill in: <list every required secret, e.g. API keys,
# DB password, JWT signing secret, internal service secret>

# 2. <Generate any local keys/certs, e.g. a JWT signing keypair —
#    say which services sign and which verify>

# 3. <Fetch any credentials from your secret manager / team lead,
#    and say exactly where each file goes>

# 4. <Log in to your container registry, if local builds pull base images>

# 5. <Install any host-level build deps>
```

---

## Local Dev — Daily Commands

**All commands run from `<config-repo>/<local-deploy-dir>/`.** (Keep the
up/down/logs commands in sync with `local_stack:` in `.aif/config.yml`.)

### Start / Stop Everything

```bash
<build-all command>    # Build all service images
<up command>           # Start all services (background)
<down command>         # Stop all containers
<clean command>        # Stop + remove volumes (full reset)
<status command>       # Show running containers
```

### Per-Service Build + Start

```bash
# Pattern: <e.g. make build-<service> then make up-<service>>
<build api> && <start api>
<build web> && <start web>       # note any implicit deps that start with it
<build worker> && <start worker>
```

### Logs

```bash
<logs command for api>
<logs command for web>
<logs command for worker>
<logs command for everything>
```

### Local Service Ports (after startup)

| Service      | URL                        |
| ------------ | -------------------------- |
| API          | http://localhost:<8040>    |
| API docs     | http://localhost:<8040>/<docs-path> |
| Web          | http://localhost:<3000>    |
| Postgres     | localhost:<5432>           |
| Redis        | localhost:<6379>           |

---

## Per-Repo Build Commands

These run from each repo's own directory (not from `<config-repo>`). List the
build / test / lint / codegen commands per repo so Claude can verify its own
work without asking:

```bash
# api (<language>)
<build command>          # e.g. go build ./...
<test command>           # e.g. go test ./...
<lint command>
<codegen command>        # e.g. regenerate API docs — note WHEN it's required

# web (<framework>)
<dev server command>
<production build command>
<lint command>
<type-check command>

# worker (<language>)
<build command>
<test command>
<lint command>
```

---

## Auth Contract (All Services)

<!-- The single most important section for security-sensitive work. Show the
     full token-exchange chain, then the table of every credential type. -->

```
Browser (<identity provider> session token)
  → web server-side proxy
    → api <token-exchange endpoint>  (<IdP token> → <internal token format>, signed with <key>)
      → downstream services (validate <internal token> with <public key / shared secret>)
```

| Auth Type         | Used By                  | Header / Format                          |
| ----------------- | ------------------------ | ---------------------------------------- |
| <IdP token>       | web → api                | `Authorization: Bearer <token>`          |
| <Internal JWT>    | api → downstream services| `Authorization: Bearer <token>`          |
| API keys          | SDK / CLI → api          | `Authorization: Bearer <key-prefix>_*`   |
| Internal secret   | service → service        | `<X-Internal-Secret-header>: <secret>`   |

**Never derive the tenant id from client-supplied headers.** Backend always
derives it from verified token claims. Any spoofable tenant header must be
ignored or rejected — state that rule here explicitly.

Optional routing/scoping headers (if any):

- `<x-scope-header-1>` — <what it scopes>
- `<x-scope-header-2>` — <what it scopes>

---

## Multi-Tenancy (Universal)

<!-- Delete this section if single-tenant. Otherwise keep it brutally short
     and absolute. Keep the key list in sync with `tenancy.keys` in
     .aif/config.yml — that's what security-reviewer and migration-analyzer
     read. -->

- `<tenant-key-1>` = <org-level scope — what it maps to in your IdP>
- `<tenant-key-2>` = <sub-tenant scope within an org, if any>
- **Every DB query, every API call, every cache key must include all tenancy keys.**
- <Any lint/static enforcement of this rule, e.g. an ESLint rule in web>

---

## Cross-Repo Data Flow

<!-- Who calls whom. Keep it to one screen — this diagram answers "where does
     this request go next?" without a single file read. -->

```
web (<framework>)
  └─→ api — primary API for all web calls (<env var holding its URL>)
        └─→ worker — <what gets delegated> (proxied through api?)

<async path, if any:>
api → <queue/event bus> → worker → <datastore>
<telemetry path, if any:>
services → <collector> → <analytics store> → <read API> → web
```

---

## Database Conventions

- **ORM**: <e.g. Bun ORM (Go services), SQLAlchemy (Python)>
- **Migrations**: <tool + style, e.g. golang-migrate with raw SQL, `CREATE TABLE IF NOT EXISTS`>
- **IDs**: <e.g. UUID v4 — never serial integers>
- **Soft deletes**: <e.g. `is_active BOOLEAN` — never hard DELETE>
- **Multi-tenant columns**: every table has <tenant-key-1> + <tenant-key-2>
- **Dev DB**: <engine + version> on `localhost:<5432>` (via the local stack)
- **Prod DB**: <engine — no hostnames here; say where connection info lives>

---

## CI/CD

- CI workflow: <shared workflow / per-repo pipelines — name it>
- Container registry: `<registry host>/<org>/`
- Environments: `<dev>` → `<staging>` → `<prod>`
- Deploys via <mechanism, e.g. Helm charts in `<config-repo>/<deploy-dir>/<env>/`>

### Commit message prefix (every repo)

<!-- If CI gates commit subjects, document the EXACT anchored regex here and
     keep it identical to `org.commit_prefix_regex` in .aif/config.yml (the
     hooks/commit-prefix-check.sh hook enforces it locally). If you have no
     gate, delete this subsection — the hook defaults to Conventional
     Commits. -->

The `<commit-check job name>` CI job rejects any commit subject that doesn't
match this anchored regex:

```
<your regex, e.g. ^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?(!)?: >
```

**Allowed prefixes:** <list them>.
**Not allowed:** <common near-misses that FAIL, so Claude doesn't guess>.

**Source of truth**: <where CI reads the allowed list from — file + key>. The
list above is a reference copy for Claude's context; if it ever drifts from
the source, the source wins.

---

## Working with Claude Code

A few norms that make every session better. Full power-user tips in
`ai-factory/tips.md`.

### Modes

- **Plan Mode** (Shift+Tab twice) for anything non-trivial. Let Claude research and propose a plan first; review it; then exit and let it execute.
- **Auto-accept edits** (Shift+Tab once) for active coding. Silences Edit/Write prompts; Bash still prompts.
- **`/clear`** between unrelated tasks. Context degrades as it fills — don't try to salvage a confused session.

### Discover what's available

- **In-session live list**: type `/agents` to see subagents active right now
- **Full inventory from terminal**: `<workspace>/ai-factory/catalog.sh`

### Subagents — delegate, don't cram

Team-shared subagents available in every session (installed via `ai-factory/install.sh`):

| Agent                    | Invoke when                                                                                                   |
| ------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `security-reviewer`      | Auditing auth, multi-tenancy, JWT handling, secret exposure                                                   |
| `cedar-policy-reviewer`  | Validating Cedar policies against the appropriate service schema (only if your org uses Cedar)                |
| `cross-repo-impact`      | "What breaks if I change X?" across every repo in `.aif/config.yml` `repos:`                                  |
| `migration-analyzer`     | SQL schema or data migration safety — locking, backfill, rollback                                             |
| `gemini-reviewer`        | Gemini has reviewed a PR — fetch + triage + apply/reject comments in bulk                                     |
| `pr-shepherd`            | Mechanical CI failures on an open PR (commit format, CVE bumps, formatter drift, lockfile drift)              |
| `local-stack-runner`     | Bring up / tear down the local docker stack (`local_stack:` in `.aif/config.yml`)                             |
| `kind-regression-runner` | Drive the e2e regression suite against a local kind cluster (`regression:` in `.aif/config.yml`)              |

**Three equivalent ways to invoke:**

1. **By name (clearest):** _"Have the security-reviewer audit this PR."_
2. **@-mention:** _"@security-reviewer please audit this PR."_
3. **Natural language:** _"Check my code for multi-tenancy leaks."_ — Claude reads each agent's `description:` and picks the right one.

Full example: _"Have the security-reviewer audit this PR. I added a new `/v1/admin/users/:id/permissions` endpoint and I'm not sure I'm deriving the tenant id correctly from the JWT."_

Subagents run in their own context window — main session stays clean.

#### Auto-invoke after every `gh pr create`

Two of these subagents are PR-attached and should fire reflexively, not on request:

- **`pr-shepherd`** — same turn as the `gh pr create` that opened the PR, dispatch in the background with the PR URL/branch. It watches CI to green and auto-fixes mechanical failures (commit-prefix format, CVE bumps, formatter drift, lockfile drift). If it stalls on its watchdog, don't fall silent — dispatch a fresh one or take over with Monitor. When the Slack MCP server is configured and `org.slack.pr_channel` is set in `.aif/config.yml`, it also posts a one-time `<!here> please review <link>` request to that channel once CI is green (skips silently if either is absent; pass `--reviewers <@U12345678,...>` (Slack member ids) to tag people or `--no-slack` to suppress).
- **`gemini-reviewer`** — only if your org uses a PR review bot (e.g. `gemini-code-assist[bot]`); skip this bullet entirely if not. As soon as the bot lands comments (often after CI settles, sometimes before), delegate to triage. Don't wait to be asked. Even after CI is fully green, still poll for bot comments — they arrive on their own schedule. Gemini posts in **two places**, so check both: `gh api repos/.../pulls/<n>/comments` (inline review comments on code) AND `gh api repos/.../issues/<n>/comments` (PR-level review summaries). Polling only the former silently misses summaries.

If you're opening the PR for the user, you own this loop until the PR is green and (where a review bot is in play) all its comments are addressed (applied or rejected with a reason on-thread). Reporting "PR opened" without these in-flight isn't done.

### Skills — multi-step workflows

**Before starting any non-trivial feature, invoke `/feature-prep` first** to decide whether your spec registry (`org.spec_registry` in `.aif/config.yml`) needs a spec PR and where the tests belong. The hook catches commit-message mistakes; the skill catches scope mistakes.

The session also auto-loads `/using-aif` (a meta-skill that maps intent → skill/agent/MCP tool) via the SessionStart hook, so you usually don't have to remember which skill is which — describe the task and the right one surfaces.

| Skill                         | What it does                                                                                                                                                                                  |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/from-issue`                 | Single command from GH issue → merge-ready PR. Classifies the issue, routes through `/debug` / `/feature-prep` / `/grill-feature` as needed, runs `/ship`, opens the PR, hands off to `@pr-shepherd`. Supports `--auto` for mechanical bug-fix / dev-tooling work (degrades silently on any architectural signal).|
| `/feature-prep`               | At the start of a non-trivial feature: spec registry entry needed? where do tests belong?                                                                                                     |
| `/grill-feature`              | Adversarial design review BEFORE coding — for architectural / cross-service / contract-touching work only. Anchored in your spec registry + ADRs (`org.adr_dir`). Default to `/feature-prep` for everyday features.|
| `/ship`                       | Pre-merge orchestrator — fans out cross-repo-impact + security-reviewer + migration-analyzer + gemini-reviewer (and cedar-policy-reviewer where relevant) in parallel, then post-deploy verification on your shared dev environment |
| `/triage-dev`                 | Investigates shared-dev-environment issues — follows the ordered `environments.dev.observability` sequence (traces/dashboards → cluster pods/events → DB state → service state)               |
| `/source-driven`              | Replaces speculation with reading the source — prefers your `mcp__<namespace>__*` tools (docs, DB schema, k8s, service APIs) when an MCP server is configured                                 |
| `/incremental-implementation` | Build in thin vertical slices with strict sequencing rules (spec first, contracts before consumers, migrations before reads)                                                                  |
| `/debug`                      | Local repro and root-cause workflow — Phase 1 = build a fast deterministic feedback loop; everything else is mechanical                                                                       |
| `/deprecate`                  | Multi-stage removal across all your repos: announce → migrate → wait → delete                                                                                                                 |
| `/git-workflow`               | Your org's commit prefixes (`org.commit_prefix_regex`), atomic commits, branch + worktree patterns                                                                                            |
| `/handoff`                    | Compact the current session into a handoff doc — per-repo branch state, open PRs, spec entries in motion, load-bearing findings, suggested resume skills. Use before `/clear`.                |
| `/release-notes`              | Multi-audience release-notes draft (customer / engineering / executive) from a git tag or range — draft only, never publishes                                                                 |
| `/dep-update`                 | Vetted dependency updates: changelog risk review per candidate, isolated branch, test-proven, one PR per coherent batch                                                                       |
| `/license-audit`              | SBOM + license policy compliance — allowed / denied / needs-review per component, with evidence for every license claim                                                                       |
| `/rotate-secrets`             | Secret-rotation choreography: expiry gate over the `secrets:` inventory, issue→deploy-alongside→verify→human-gate→revoke                                                                      |
| `/doc-drift`                  | Diff-derived stale-doc hunter — extracts the public surfaces a change moved, fixes every doc that mentions them                                                                               |
| `/threat-model`               | STRIDE threat model from a spec/RFC before implementation — refuted threats, severity-ranked mitigation punch list                                                                            |
| `/add-detector`               | Example org-specific scaffold: a new detector + telemetry signal contract. Adapt to your services or delete.                                                                                  |
| `/new-admin-module`           | Example org-specific scaffold: the 6-file module pattern for your primary API. Adapt to your services or delete.                                                                              |

The toolkit also ships the **AIF pipeline** — a full spec-driven lifecycle for feature work: `/spec` → `/architect` → `/validate` → `/proceed` (end-to-end pipeline) → `/review` → `/wrapup`, plus `/sprint` (parallel REQs), `/adversary` (adversarial artifact review), `/bugfix`, `/status`, `/manifest`, `/analyze`, and `/optimize`. Run `/init` once in a repo to bootstrap its `.aif/` structure. See `ai-factory/README.md` for the full catalog; `/using-aif` routes across both families.

**Two equivalent ways to invoke:**

1. **Slash command (fastest):** `/triage-dev`, `/ship`, etc.
2. **Natural language:** _"Something's broken in our shared dev environment"_ / _"I want to add a new detector for phishing."_ — Claude sees the skill's description and offers to invoke it.

### References — load on demand

Detailed checklists in `ai-factory/references/` — NOT auto-loaded; skills and subagents pull them in when relevant:

| File                            | Load when                                                                    |
| ------------------------------- | ---------------------------------------------------------------------------- |
| `known-warts.md`                | Hit a confusing CI/test/contract behavior — check before chasing it as a bug |
| `mcp-tools-cheatsheet.md`       | About to investigate live state — pick the right MCP tool family             |
| `multi-tenancy-checklist.md`    | Touching DB queries, cache keys, API handlers                                |
| `jwt-checklist.md`              | Touching auth — token types, issuance, verification                          |
| `migration-safety-checklist.md` | Authoring or reviewing a SQL migration                                       |
| `commit-prefix-check.md`        | About to commit; what subject lines pass your org's commit gate              |
| `regression-markers.md`         | Picking test markers / regression profile (`regression.profiles`)            |
| `telemetry-pipeline.md`         | A metric/scan result is missing from a dashboard — debug the pipeline hop by hop |
| `trigger-recipes.md`            | Running a skill unattended (CI/cron/headless) with a least-privilege role overlay |

### Per-repo CLAUDE.md — root + nested

Big repos use a **lean root + nested CLAUDE.md** pattern to keep always-loaded context small. Open a file under a subtree with its own nested `CLAUDE.md` and only that file loads — not the entire repo's design system or schema reference.

<!-- Replace these example rows with your repos that use nested CLAUDE.md files. -->

| Repo   | Where the nested files live                                      |
| ------ | ---------------------------------------------------------------- |
| `web`  | `packages/ui/`, `packages/api/`                                  |
| `api`  | `internal/<domain-1>/`, `internal/<domain-2>/`                   |

Adding a nested CLAUDE.md: keep it scoped to its subtree, ≤700 lines, no duplication from the root. Link out to deeper detail rather than inlining.

### Known-warts inbox (reflection hook)

A Stop hook (`session-reflect.sh`) fires after substantial sessions (≥3 edits) and asks the current Claude to capture any non-obvious gotcha into the known-warts inbox (`~/.claude/aif-references/known-warts-inbox.md`). Periodically (e.g., weekly), review the inbox, promote real entries into `known-warts.md`, and clear what's noise. Disable per session with `AIF_REFLECT_OFF=1 claude`.

### Model + effort

Default to **Opus 4.7** at **`xhigh`** effort for platform coding. Bump to **`max`** for security or migration work. Drop to Sonnet for "just apply this pattern" tasks.

### Verify your work

Every non-trivial prompt should include how Claude knows it's done. Examples:

- `After each edit, run 'go vet ./...' and fix any new warnings before continuing.`
- `Start the web app and confirm the new /usage page renders without errors.`
- `Regenerate the API docs if any handler signature changed.`
