---
name: triage-dev
description: Investigates a problem in your org's shared dev environment (errors, latency spike, broken endpoint, "something's wrong on dev"). Walks your observability sources in the order configured in `.aif/config.yml` — traces/dashboards → orchestrator state → data store → service-specific state — to localize the root cause without speculation. Use when the question is "what's broken in the shared dev environment?" rather than a local repro.
---

# Triage dev — what's wrong in the shared dev environment?

## Overview

Most shared dev environments auto-deploy on every merge to main. When something goes wrong there — error spikes, broken endpoints, missing data — the failure mode is "speculate from logs you can't see." This skill replaces speculation with the right query in the right order.

This is the shared-environment sibling to `/debug` (which covers local repro). When the question is "what's broken in the shared dev environment?" — use this. When the question is "why is my unit test failing?" — use `/debug`.

## Configuration

Read these keys from `.aif/config.yml` before starting:

- **`environments.dev.observability`** — an ORDERED list of where to look when the shared environment is broken. The investigation order in Steps 2–6 follows this list. If the key is absent, fall back to the generic order used below: traces/dashboards → orchestrator state → data store → service-specific state.
- **`environments.dev.name`** — what your org calls this environment; use it in your summary.
- **`mcp.namespace`** — if set, prefer MCP tools named `mcp__<namespace>__*` for every step, and read `~/.claude/aif-references/mcp-tools-cheatsheet.md` for the intent → tool map. If no MCP server is configured, use whatever direct access you have (`kubectl`, a database client, `gh`, dashboards the user can paste from). If you have **no** access to a source a step needs, say exactly what access is missing and stop — never guess at live state.

## When to use

- "Error rate spiked after the last deploy"
- "An endpoint returns 500 on the shared dev environment but locally it's fine"
- "My PR auto-deployed and now a downstream service is throwing"
- "An integration test against the shared environment fails but the unit tests passed"
- A user reports a bug specific to the shared environment

**Don't use** for:

- Local stack issues → `local-stack-runner` agent + `local_stack.logs_command`
- Local regression-suite failures → the kind-regression-runner agent (when `regression:` is configured)
- Production issues → your org's incident process; this skill is scoped to the shared dev environment

## Process

### Step 1 — confirm the failure shape

Before opening any tool, write down in one line:

- What's failing? (endpoint, page, signal, missing data)
- Since when? (after the last deploy / N minutes ago / always)
- For whom? (specific tenant, all tenants, internal only)

If you can't answer "since when," start with your traces/dashboard overview on the suspected service and look for the inflection point.

### Step 1b — check the runbooks (when `org.runbooks_dir` is configured)

Before improvising an investigation, check whether this failure shape already has a runbook: grep `org.runbooks_dir` (from `.aif/config.yml`) for the symptom's keywords (service name, error string, signal name). If one matches:

- **Follow its investigation order** over this skill's generic Steps 2–6 — the runbook encodes what actually broke here before.
- **Execute read-only steps directly** (queries, log pulls, status checks) and record what each showed.
- **Never auto-execute mutating steps** (restarts, config changes, deletes, scaling) — present each with the runbook's rationale and the evidence gathered so far, and let the human trigger it. A runbook is context, not authorization (ethos #6 gates still apply).
- Cite the runbook path in the output so the next person finds it faster.

No `org.runbooks_dir`, or no match: continue to Step 2 and — if the investigation uncovers something runbook-worthy — suggest writing one as a follow-up.

### Step 2 — traces/dashboards: where in the request flow?

Use the first entry in `environments.dev.observability` (typically a tracing or dashboards tool; via MCP this is a `mcp__<namespace>__*` tool family):

```
overview / error-rate view    → error rate, p99 latency vs baseline
                                 pick the inflection point — that's the start of the window
failing traces in the window  → read 1–3 traces in detail to see which span fails first
hot-path breakdown            → if it's dependency- or tool-call related, see what's hot
```

You should leave Step 2 with: **the service that fails first, and the span/operation name.**

### Step 3 — orchestrator: is the service itself sick?

For the service identified in Step 2, inspect cluster/orchestrator state (via MCP tools if exposed, else `kubectl` or your platform's equivalent):

```
list pods / instances      → all Running? new image rolled out cleanly?
recent events              → ImagePullBackOff, OOMKilled, Evicted in last 30 min?
describe unhealthy pod     → why? readiness/liveness probe failing?
tail the failing pod's logs → panics, repeated errors, DB connection failures
```

You should leave Step 3 with: **either "service is healthy, problem is data/config" → Step 4, or "service is sick, here's the root cause" → fix.**

### Step 4 — data: is the input the problem?

For services that depend on a data store, inspect it (via MCP DB tools if exposed, else a read-only client):

```
list tables         → confirm expected tables exist
describe table      → schema matches expectation? new column from a recent migration present?
targeted query      → does the row the request expects actually exist?
                      are the tenancy keys (`tenancy.keys`) what you expect?
```

If a service fronts its own analytics store, query it through that service's own tools rather than direct DB access.

You should leave Step 4 with: **either "data is fine, regression is in code" or "data is missing/corrupt, backfill or restore."**

### Step 5 — config: did a recent deploy change config?

```
inspect mounted config (configmaps or equivalent) → has the config the failing service mounts changed?
inspect deployments                                → what image SHA is running? does it match the latest main?
```

If the config changed but the pod didn't restart, the new config isn't live — that's often the bug.

### Step 6 — service-specific state

If the failing service exposes its own state or health endpoints (active rules or policies, registered plugins or detectors, a synthetic self-test, `/healthz`) — via MCP tools or plain HTTP — query them now:

```
active configuration state  → expected rules/policies/plugins present?
synthetic positive input    → does the service respond correctly to a known-good request?
health endpoint             → the service's own view of its health
```

### Step 7 — dev-only escape hatches

If steps 1–6 don't localize the cause, and your MCP server (or access) provides them:

```
internal HTTP request  → hit an internal endpoint not exposed externally
exec in pod            → last resort; run a single command inside a pod
```

Exec-in-pod is the most invasive tool here. Use it only when you've ruled out everything cheaper.

## Output

End with a triage summary:

```markdown
## Triage: <one-line failure>

### Failure shape

- What: <endpoint / signal>
- Since: <time / deploy SHA>
- Scope: <tenants / users affected>

### Localized to

- Service: <name>, span: <operation>
- Evidence: <tool output that pinpointed it>

### Root cause

- <one-line cause>
- <evidence from Step 3/4/5/6>

### Fix

- <PR diff / config change / data backfill>
- <who's making it / which repo>

### Verification after fix

- <which queries confirm green>
```

## Rationalizations (and rebuttals)

| You'll be tempted to think…                            | Why it's wrong                                                                                                                                                                |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| "I'll just read the code; the bug is probably obvious" | The deploy is what changed. The code-without-context view misses config drift, image-rollout state, and data shape. Start with the live sources.                               |
| "Skip the traces, jump straight to pod logs"           | You'll read the wrong pod's logs. Traces tell you which span fails first; without them, you guess.                                                                             |
| "Reproduce locally first"                              | Often the bug is environment-specific (real data shape, real auth chain). Local repro is for the bug class, not always the bug. Triage on the shared environment; repro after. |
| "I'll exec into the pod to poke around"                | Exec-in-pod is the last tool, not the first. Steps 2–6 answer most questions without it.                                                                                       |
| "The query returned no results, must be fine"          | Empty trace results likely mean the trace isn't being emitted — investigate the telemetry pipeline, not the user-facing symptom.                                               |

## Red flags

- You started writing fix code before completing Step 2. You don't know where the bug is yet.
- You used exec-in-pod in Step 1 or 2. Massive overkill; back up.
- You read pod logs without first knowing which pod. Traces pinpoint the right one.
- You explained the bug from memory of "what we changed last week." Verify against the live sources — your memory is wrong.
- Your observability source is unreachable and you're improvising. Stop, surface exactly what access is missing, ask the user how to proceed.

## Verification

Triage is done when:

- [ ] Failure shape (what, since, scope) is written down
- [ ] Service + span localized via traces, not guessed
- [ ] Either orchestrator state or data state has produced concrete evidence of the cause
- [ ] Fix is named (PR / config change / backfill)
- [ ] Post-fix verification queries are listed (the same queries, expected to be green)

## Anti-patterns

- Speculating before opening the configured observability sources
- Reading pod logs before identifying the pod via traces
- Using exec-in-pod as the first tool
- Assuming a config change took effect without checking pod restart
- Ignoring the trace view because "logs are easier to read"
- Diagnosing shared-environment issues by re-running locally — the environments diverge in real ways
- Fabricating live state when no MCP server or cluster access is configured — say what's missing and stop
