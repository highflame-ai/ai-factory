# MCP Tools — Intent → Tool Cheatsheet (fill-in template)

If your org runs an MCP server that exposes live platform state to Claude Code, fill this file in: map each of its tools to the **intent** it answers, so Claude reaches for MCP instead of speculating, reading stale docs, or guessing at live state.

Tool names follow `mcp__<namespace>__*`, where `<namespace>` comes from `mcp.namespace` in `.aif/config.yml` (e.g. `acme-platform` → `mcp__acme-platform__db_query`).

**If no MCP server is configured** (`mcp.namespace` absent or the server unreachable): say so and use local alternatives — read the code, `gh` for forge state, `kubectl` if you have cluster access. Never fabricate live state.

> **No fallback fabrication.** When a tool returns "mcp server unreachable," surface the failure and stop — do not improvise or invent plausible output. If your laptops can't reach the shared environment directly (no `kubectl` access), the MCP server may be the *only* window into it; a failure means "unknown," not "probably fine."

## Recommended organization: tool families by intent

Structure your map as families. The three below (docs, db, k8s) cover most platform MCP servers; add a family per additional subsystem your server exposes (observability, feature flags, your detection service, ...).

### Architecture / contracts (docs family)

| Intent                                                                  | Tool                                                     |
| ----------------------------------------------------------------------- | -------------------------------------------------------- |
| "What does service X promise?" / "What's the contract between A and B?" | `mcp__<namespace>__docs_list` → `mcp__<namespace>__docs_read` |
| "Is there an ADR or spec entry for this?"                               | `docs_list` (search the architecture catalog)            |

### Database (read-only, shared dev environment)

| Intent                                                   | Tool                                  |
| -------------------------------------------------------- | -------------------------------------- |
| "What tables exist in this service's DB?"                | `mcp__<namespace>__db_list_tables`    |
| "What columns / indexes does this table have?"           | `mcp__<namespace>__db_describe_table` |
| "Is the data shape what I expect? Did the backfill run?" | `mcp__<namespace>__db_query`          |
| "Will this query be fast enough?"                        | `mcp__<namespace>__db_explain`        |

Expose these through a read-only role so they're safe by construction. Do not attempt `INSERT`/`UPDATE`/`DELETE`.

### Kubernetes (shared dev cluster)

| Intent                                                    | Tool                                                                   |
| --------------------------------------------------------- | ----------------------------------------------------------------------- |
| "Did the new deploy roll out cleanly?"                    | `mcp__<namespace>__k8s_get_pods` (look for `Running` + new image SHA)  |
| "Why is the pod crash-looping?"                           | `mcp__<namespace>__k8s_describe_pod`                                   |
| "Show me boot logs for the latest pod."                   | `mcp__<namespace>__k8s_pod_logs`                                       |
| "Was the deployment annotation actually applied?"         | `mcp__<namespace>__k8s_get_deployments`                                |
| "What configmap is mounted for service X?"                | `mcp__<namespace>__k8s_get_configmaps`                                 |
| "Are there ImagePullBackOff / OOMKilled events?"          | `mcp__<namespace>__k8s_get_events`                                     |
| "What's exposed on this service / ingress?"               | `mcp__<namespace>__k8s_get_services`, `k8s_get_ingresses`              |
| "I need to run a one-off command in a pod."               | `mcp__<namespace>__dev_exec_in_pod` (last resort — prefer logs/describe) |
| "Hit an internal endpoint that's not exposed externally." | `mcp__<namespace>__dev_http_request`                                   |

### Your additional families (fill in)

| Intent                                   | Tool                       |
| ---------------------------------------- | --------------------------- |
| "Has the error rate or p99 spiked?"      | `mcp__<namespace>__<tool>` |
| "What's the live state of <subsystem>?"  | `mcp__<namespace>__<tool>` |

## When NOT to use MCP

Fill these in for your setup; typical boundaries:

- **Local docker stack triage** — use the `local-stack-runner` agent + your `local_stack.logs_command`. The MCP server usually only sees the shared environment.
- **Local cluster regression runs** — use the kind-regression-runner agent. Same scoping caveat.
- **Static code questions** — read the file. Don't `docs_read` the architecture repo if the question is about a function in a service repo.
- **Anything in prod** — if your MCP server is scoped to the shared dev environment, prod investigations require human-in-the-loop.

## Common combos (fill in / adapt)

- **Post-merge verification** (used by `/ship`): `k8s_get_pods` → `k8s_pod_logs` (boot errors) → observability overview (error rate vs baseline)
- **Dev triage** (used by `/triage-dev`): observability overview → failing events/traces → `k8s_get_events` → `k8s_pod_logs` → `db_query` if data state suspected
- **Migration verification** (used by `migration-analyzer`): `db_describe_table` (column added?) → `db_query` (backfill complete?)
