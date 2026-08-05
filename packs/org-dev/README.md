# org-dev — Org Feature Delivery

Day-to-day feature delivery as a governed pipeline: the org-workflow skills
this repo already ships, sequenced under capability roles with gates. The pack
is **org-agnostic** — every org-specific fact (what drives your local stack,
where your regression suite lives, which columns scope a tenant, what commit
subjects your CI accepts) resolves at runtime from the repo's `.aif/config.yml`.
Fill the config and the same pack does production-grade delivery for your
platform; leave a section out and the corresponding step degrades exactly the
way the underlying skill documents.

## Phases

| Phase | Skill | Role | Gate (exit) | What happens |
|---|---|---|---|---|
| `prep` | `/feature-prep` | implementer | — | Does the spec registry need an entry first? Where do tests belong (org regression vs repo-local)? Escalates to `/grill-feature` itself when its architectural criteria fire. |
| `implement` | `/incremental-implementation` | implementer | `tests_pass` (`make test`) | Thin vertical slices, one repo at a time, working state at every step. Retries twice on a red gate. |
| `verify` | inline prompt | orchestrator | — | Blast-radius decision: cross-cutting + `regression:` configured → org regression suite via `kind-regression-runner` (cheapest covering profile); otherwise repo-local tests, stated explicitly. Hands-on flows go through `local-stack-runner` (`local_stack:`). Tenancy-touching changes must demonstrate cross-tenant isolation. |
| `review` | `/review` | reviewer | `no_blocking_findings` | Read-only multi-agent bench. The role physically cannot write or egress. |
| `ship` | `/ship` | orchestrator | — | Reviewer fan-out → go/no-go → PR → CI shepherded to green with review comments resolved (see ETHOS). |

## Config keys each phase consumes

| Key | Consumed by | Absent → |
|---|---|---|
| `org.spec_registry` | prep, ship | no registry gate; prep collapses to `NO_UPDATE` |
| `regression:` (`repo`, `run_command`, `profiles`) | prep, verify | every test is repo-local, stated explicitly |
| `local_stack:` (`dir`, `up/down/logs_command`) | verify | agent inspects the repo for a stack driver and asks before running |
| `tenancy.keys` | verify, review, ship | tenant-isolation checks skipped, stated in the report |
| `org.commit_prefix_regex` | implement, ship | Conventional Commits default |
| `environments.dev` + `.observability` | ship (post-merge verify) | manual checklist handed to the user |
| `mcp.namespace` | verify, ship | no fabricated live state; manual access or stop |
| `repos:` / `merge_order` | implement, verify | single-repo behavior |

## Trust

The `tests_pass` gate declares `make test` as a host command. Commands from a
pack run **only after the operator trusts it** (`codeoid pack install org-dev
--trust`, or `codeoid pack trust org-dev`); untrusted, the gate fails closed
and the pipeline parks for a human. Skill linking follows the same opt-in.

## Make it yours

1. Install this registry's skills/agents (`./install.sh` at the repo root) —
   the pack references them by slash command.
2. `codeoid pack registry add <this repo's git URL> --name ai-factory`
3. `codeoid pack install org-dev --trust`
4. Give each code repo a `.aif/config.yml` — start from a
   [`skills/presets/`](../../skills/presets/) stack shape, or from your org's
   own filled seed (keep real hostnames/channels/service names in **your**
   repo, not this one; see the presets README's "stack shape, not company
   configuration" rule). Copies per repo work, but the zero-drift pattern is
   a single org-wide config file that every repo's `.aif/config.yml`
   **symlinks to** — skills read through the link transparently. With a
   shared config there's no per-repo `primary:` flag; the repo you invoke
   the pipeline in is the primary for that run.
5. `codeoid pipeline run --pack org-dev --goal "<task>"`
