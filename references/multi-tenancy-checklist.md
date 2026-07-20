# Multi-Tenancy Checklist

Parameterized on `tenancy.keys` in `.aif/config.yml` — the ordered list of columns/claims that scope tenant data (e.g. `account_id` as `<tenant-key-1>`, `project_id` as `<tenant-key-2>`). Many platforms are multi-tenant at two levels:

- `<tenant-key-1>` — org-level scope (e.g. `account_id`, mapped to your identity provider's organization)
- `<tenant-key-2>` — sub-tenant scope within an org (e.g. `project_id`)

**Every DB query, every API call, every cache key must include ALL keys listed in `tenancy.keys`.** No exceptions. A missing filter = cross-tenant data leak.

If `tenancy.keys` is absent from `.aif/config.yml`, say so and ask whether the project is single-tenant; if it is, this checklist doesn't apply. Don't guess key names from the schema.

## Where the IDs come from

| Code path                          | Source                                                                                                                                 |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Backend services                   | Verified token claims via the auth middleware. **Never** from headers, query params, or request body.                                  |
| Frontend (server actions / hooks)  | Captured once at the data-access layer (e.g. a `useAccountInfo()`-style hook), passed explicitly into query functions — never re-derived inside them. Enforce with a lint rule if your framework allows it. |
| SDK / external clients             | Derived from the API key the request was authenticated with.                                                                            |

Client-supplied tenant headers (e.g. `x-account-id`) are **ignored or rejected** at every service boundary. Setting one is a code smell.

## DB query checklist

- [ ] Every `SELECT` filters on ALL tenant keys (`<tenant-key-1> = ?` AND `<tenant-key-2> = ?`)
- [ ] Every `INSERT` sets all tenant-key columns (NOT NULL)
- [ ] Every `UPDATE` `WHERE` clause includes all tenant keys
- [ ] Every `DELETE` (or soft-delete flip) includes all tenant keys
- [ ] Every index that matters is multi-column starting with the tenant keys, e.g. `(<tenant-key-1>, <tenant-key-2>, ...)`
- [ ] If soft-deletes apply, partial indexes use `WHERE is_active` (or your equivalent) to skip dead rows

## API handler checklist

- [ ] Each tenant key is taken from verified token claims, not the request
- [ ] Request DTOs do NOT carry tenant-key fields. If they do, ignore them and overwrite from claims.
- [ ] Response payloads do not embed another tenant's IDs (e.g. via a join that escaped a filter)

## Cache key checklist

- [ ] Cache keys (Redis, memcached) include ALL tenant keys, e.g. `t1:{<tenant-key-1>}:t2:{<tenant-key-2>}:resource:{id}`
- [ ] In-process LRU keys include all tenant keys
- [ ] **Never** key on `id` alone — even if IDs are UUIDs and "globally unique," a stale entry serving the wrong tenant is still a leak

## Frontend checklist

- [ ] Tenant keys captured once at the hook/loader level, passed explicitly into query functions
- [ ] No re-derivation of a tenant key inside a query function (enforce with a lint rule where possible; do not disable it)
- [ ] Any optional routing headers that carry tenant hints are scope, not auth — they may narrow but never broaden access

## Cross-service checklist

- [ ] Service A → Service B requests carry the user's verified token (or an internal service secret for internal-only paths)
- [ ] Service B re-derives the tenant keys from the token; it does not trust A's claim
- [ ] Trace spans include the tenant keys as attributes so traces are tenant-attributable

## Red flags

- A query without a `<tenant-key-1>` predicate. Stop, add it.
- A handler that pulls tenant IDs from path params, query strings, or the body. Stop, take from claims.
- A cache miss producing data with the wrong tenant ID. The key is bugged.
- An admin/support endpoint that "needs to see all accounts." It still scopes per-call; admin = tenant key from the impersonation context, not unfiltered.

## When you find a violation

This is a **security finding**. Fix in the same PR; do not punt. If the violation is in code that's already shipped:

1. Patch immediately (filter added)
2. Audit DB logs / traces for evidence of cross-tenant reads (via MCP observability tools if `mcp.namespace` is configured, otherwise your logging/tracing backend)
3. File a security ticket if data egress is plausible
