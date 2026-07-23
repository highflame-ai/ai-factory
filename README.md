# ai-factory

**0→1 with an AI coding agent is easy. 1→100 is where it gets hard** — the code that survives review, scales past the demo, and doesn't quietly rot the codebase over months. That's where ai-factory comes in.

A complete spec-driven development practice for AI coding agents — skills, agents, deterministic hooks, and a role-based capability model — installed once and parameterized to your org through config, not forks.

<!-- TODO: demo — replace with a vhs/asciinema GIF of a real /proceed run (feature request → opened PR). Tape script: assets/demo.tape. Must be a genuine run, not staged output. -->

**Why ai-factory**

- **Faster** — across our own development at Highflame, the spec-driven pipeline plus parallel sprint orchestration routinely delivers **3–5x**: features/PRs shipped, bugs resolved, and time-to-merge, vs. ad-hoc AI-assisted coding. *(our internal experience — your mileage will vary)*
- **Less slop** — deterministic gates, an adversarial multi-agent review bench, and a verification-is-non-negotiable ethos: unreviewed AI output can't reach `main`.
- **Leaner context** — heavy research and review run in subagents with their own context windows; the main session stays focused.

**Two ways to run it:**

- **Standalone in [Claude Code](https://claude.com/claude-code)** — 41 skills as slash commands (`/spec → /architect → /proceed → /ship`), symlinked live into every session. Clone, `./install.sh`, go.
- **Under [codeoid](https://github.com/highflame-ai/codeoid)** — the same methodology as a declarative pack on codeoid's multi-session runtime, with per-agent identity and cross-session memory: `codeoid run --pack aif-sdlc`.

## How it's organized

Three layers:

1. **The AIF pipeline** — a spec-driven development lifecycle (spec → architect → validate → implement → reflect → review → ship) with parallel sprint orchestration, a multi-agent review bench, and the `aif` health CLI.
2. **The org-workflow layer** — day-to-day engineering skills (issue-to-PR orchestration, debugging, deprecation, git conventions, session handoffs, environment triage), review agents, and deterministic hooks. Everything org-specific resolves through `.aif/config.yml` — nothing is hardcoded, and every skill states what it does when a config key is absent.
3. **The pack registry** ([`packs/`](packs/)) — the methodology as declarative [codeoid](https://github.com/highflame-ai/codeoid) packs (`schema: codeoid/pack@v1`). A pack is data-only (a `pack.yaml` + capability roles + constitution); codeoid runs its governed phase pipeline. Contribute a pack once, and any team can select it. See [`packs/README.md`](packs/README.md) — first pack: [`aif-sdlc`](packs/aif-sdlc/).

## Setup

```bash
git clone https://github.com/highflame-ai/ai-factory.git
cd ai-factory && ./install.sh
```

`install.sh` is idempotent and repair-capable. It symlinks:

| Link | Target | Consumed by |
|---|---|---|
| `~/.claude/skills` | `skills/` | every skill (`/spec`, `/ship`, …) |
| `~/.claude/agents` | `agents/` | every subagent (`@security-reviewer`, …) |
| `~/.claude/aif-hooks` | `hooks/` | the hooks block in each repo's `.claude/settings.json` |
| `~/.claude/aif-bin` | `bin/` | sidecar helpers |
| `~/.claude/aif-references` | `references/` | on-demand checklists |
| `<workspace>/CLAUDE.md` | `workspace-CLAUDE.md` | always-loaded workspace context (fill-in template). Workspace root: `AIF_WORKSPACE` env → `~/.claude/aif/config.yml` `workspace.root` → the clone's parent dir |

It also writes the `aif` CLI shim to `~/bin` (`doctor`, `check`, `agents render`, `compile`, `renumber`), scaffolds `~/.claude/aif/config.yml` (delegation **off** by default), and finishes with `aif doctor` — a full environment health check that prints a copy-pasteable fix for every failure. `./install.sh --dry-run` previews; `--repair` re-stamps after moving the clone.

### Make it yours

The journey: install → fill in `workspace-CLAUDE.md` and the machine config (`~/.claude/aif/config.yml`) → run `claude` → `/init` in each code repo to bootstrap its `.aif/` structure → then fill that repo's `.aif/config.yml` (optionally starting from a [`skills/presets/`](skills/presets/) starter). Along the way, an adopting org customizes five things (details in [`examples/README.md`](examples/README.md)):

1. **`.aif/config.yml`** per repo — scaffolded by `/init` (from [`skills/templates/config-template.yml`](skills/templates/config-template.yml)) when you opt into cross-repo coordination, or copied in afterward from a preset — stack, sibling repos, and the `org:`/`environments:`/`mcp:`/`local_stack:`/`regression:`/`tenancy:` sections that drive the org-workflow skills.
2. **`workspace-CLAUDE.md`** — the always-loaded platform-context template (service map, auth contract, conventions).
3. **Fill-in references** — MCP cheatsheet, regression markers, known-warts registry, tenancy/JWT checklists.
4. **Hook configuration** — `org.commit_prefix_regex` (or `AIF_COMMIT_PREFIX_REGEX`) to mirror your CI's commit gate; add your org's key prefixes to `hooks/secret-scan.sh`.
5. **Your own skills and agents** — skeletons and house rules in `examples/`.

## Skills

### AIF pipeline (spec-driven lifecycle)

| Skill | Description |
|-------|-------------|
| `/init` | Bootstrap `.aif/` structure in a repo |
| `/onboard` | Adopt the toolkit in an existing codebase — drafts the service map, starter experts, conventions, and config for review |
| `/measure` | Measure whether the toolkit is paying off — delivery/quality metrics from git, PRs, and `.aif/` artifacts, with honest caveats |
| `/spec` | Write requirement specs from feature requests |
| `/architect` | Design architecture and break requirements into tasks |
| `/validate` | Validate any AIF phase output before advancing |
| `/proceed` | End-to-end pipeline: validate → architect → implement → reflect → review → PR → wrapup |
| `/sprint` | Parallel pipeline orchestrator — multiple `/proceed` runs across REQs (`--workflow` engine) |
| `/reflect` | Post-implementation self-review before formal review |
| `/review` | Multi-agent code review (correctness, quality, architecture, tests, security) |
| `/adversary` | Adversarial review of any artifact — assumes it is wrong and tries to prove it |
| `/canary` | Canary deployment with smoke tests |
| `/wrapup` | Close out a feature — commit, merge, deploy, update artifacts |
| `/bugfix` | Streamlined bug fix workflow |
| `/status` / `/manifest` | Local / remote-derived view of in-flight AIF work |
| `/analyze` | Codebase health audit |
| `/optimize` | API cost & performance scanner |
| `/template-drift` | Detect drift between a project's `.aif/templates/` and the toolkit's |

Core workflow:

```
/spec → /validate → /architect → /validate → implement → /reflect → /review → merge → /wrapup
```

### Org workflow

| Skill | Description |
|-------|-------------|
| `/using-aif` | Meta-skill routing table — injected at SessionStart |
| `/from-issue` | Issue → merge-ready PR orchestrator (classify, route, implement, ship, babysit CI) |
| `/feature-prep` | Does the spec registry need an entry first? Where do tests go? |
| `/grill-feature` | Adversarial design review before architectural work |
| `/ship` | Pre-merge orchestrator — parallel reviewer fan-out → go/no-go → post-deploy verify |
| `/triage-dev` | Investigate your shared dev environment in a configured observability order |
| `/source-driven` | Read the authoritative source (config, code, MCP) instead of guessing |
| `/incremental-implementation` | Thin vertical slices, one repo at a time |
| `/debug` | Local repro and root-cause; Phase 1 = fast deterministic feedback loop |
| `/deprecate` | Multi-stage removal across your configured repos |
| `/git-workflow` | Commit prefixes (configurable regex), atomic commits, branching, worktrees, PR flow |
| `/handoff` | Compact a multi-repo session into a handoff doc |
| `/release-notes` | Multi-audience release-notes draft (customer, engineering, executive) from a git tag or range |
| `/dep-update` | Vetted dependency updates — changelog risk review, isolated branch, test-proven, one PR per batch |
| `/license-audit` | SBOM + license compliance — resolve every component's license, judge against `org.license_policy` |
| `/rotate-secrets` | Proactive secret rotation — expiry gate over the `secrets:` inventory, overlap-pattern rotation, human gate before revoke |
| `/audit-permissions` | Review and prune risky standing Claude permission grants in `.claude/settings*.json` (pairs with `aif doctor`'s `permissions-audit`) |
| `/doc-drift` | Find and fix docs made stale by a change — diff-derived surfaces, stale vs missing classification |
| `/threat-model` | STRIDE threat model from a spec/RFC — assets, trust boundaries, refuted threats, mitigation punch list |
| `/expert` | Curate a domain expert — path-scoped context distilled from your docs, injected only when a change touches its domain |
| `/add-detector` | Template: scaffold a module in an extensible service, following your documented pattern |
| `/new-admin-module` | Template: scaffold a CRUD module (schema → migration → repository → service → handler → registration) |

## Agents

26 subagents in [`agents/`](agents/), each with tier-based model selection rendered by `aif agents render` (config: `~/.claude/aif/config.yml`).

- **Review bench**: correctness-reviewer, security-auditor, architecture-reviewer, quality-reviewer, code-quality-auditor, test-auditor, reflector, adversary
- **Scanners/explorers**: api-cost-scanner, db-perf-scanner, latency-scanner, architecture-mapper, convention-auditor, feature-tracer, integration-explorer, delegate-pre-pass
- **Pipeline**: task-implementer, pipeline-runner
- **Org workflow**: security-reviewer (invariant-driven audit), cross-repo-impact, migration-analyzer, pr-shepherd, gemini-reviewer, cedar-policy-reviewer (if you use Cedar), local-stack-runner, kind-regression-runner

## Experts — path-scoped domain context

[`/expert`](skills/expert/SKILL.md) curates a **domain expert**: dense context distilled from your own docs and code, stored at `.aif/experts/<name>.md`, and injected into a task **only when the change touches that domain** (matched by the expert's `applies_to` globs). Context engineering — React context on a React change, DynamoDB context on a data-access change, neither on unrelated work. `/review` activates matching experts automatically. `workspace-CLAUDE.md` holds facts true everywhere, `references/` are cross-cutting checklists, lessons are relevance-ranked incidents, experts are path-scoped domain knowledge. The `applies_to` globs are also the future compile key for path-scoped rules in other assistants (Copilot `applyTo`, Cursor globs) — that emission is the next phase.

## Roles — one capability definition, every agent runtime

[`roles/*.yaml`](roles/) is the single source of truth for what each agent role may do. A reviewer declares `{envelope: [read, grep, glob, bash], write: false}` once, and `aif compile` emits it as:

- **Claude** — validation of `agents/*.md` `tools:` frontmatter (the native layer; `--check` fails on any agent exceeding its role's envelope), plus [`compiled/claude/`](compiled/claude/) per-role settings overlays for headless/CI sessions
- **Codex** — [`compiled/codex/config.toml`](compiled/codex/config.toml) sandbox profiles per role
- **Copilot** — [`compiled/copilot/`](compiled/copilot/) paste-in role boundaries (convention — Copilot has no enforcement surface)
- **Cedar** — [`compiled/cedar/`](compiled/cedar/) schema + policies, for orgs enforcing agent capabilities at a gateway

Exceptions are declared in the role file with a reason, never quietly in an agent's own frontmatter. `aif compile --check` is the drift gate. This is what makes the toolkit's practice portable across agent runtimes rather than Claude-only.

## Hooks

Deterministic gates in [`hooks/`](hooks/), wired through each repo's `.claude/settings.json`. All wrapped in `if [ -x … ]` so machines without the install no-op silently.

| Hook | Event | Does |
|---|---|---|
| `session-start-skills.sh` | SessionStart | Injects the `/using-aif` routing table |
| `go-format.sh`, `ts-format.sh`, `py-format.sh`, `rust-format.sh` | PostToolUse (Edit\|Write) | gofmt/goimports, prettier, ruff, rustfmt |
| `secret-scan.sh` | PreToolUse (Bash) | Blocks secret exposure and destructive commands |
| `commit-prefix-check.sh` | PreToolUse (Bash) | Enforces your CI's commit-subject regex (`AIF_COMMIT_PREFIX_REGEX` → `org.commit_prefix_regex` → Conventional Commits) |
| `precommit-gate.sh` | PreToolUse (Bash) | Static analysis on staged files at `git commit` time |
| `session-reflect.sh` | Stop | One reflection turn → appends warts to the known-warts inbox |

## Settings distribution

`skills/templates/settings.example.json` is the shared per-repo `.claude/settings.json` (permissions + hooks). Maintainers roll it out across a workspace with:

```bash
tools/fleet/distribute-settings.sh -n    # dry-run: every git repo in the workspace
AIF_REPO_GLOB='acme-*' tools/fleet/distribute-settings.sh   # narrow to a repo glob
tools/fleet/open-settings-prs.sh         # open a PR per modified repo
```

Both scripts resolve the workspace root the same way as `install.sh`: `AIF_WORKSPACE` env → machine config `workspace.root` → the clone's parent directory.

`/init` copies the richer [`skills/templates/claude-settings-template.json`](skills/templates/claude-settings-template.json) (same hooks, plus the AIF pipeline allow/ask lists) into projects it bootstraps.

## Project structure (after `/init`)

```
.aif/
  ETHOS.md           # copy of the toolkit's ETHOS.md (keeps skills working inside git worktrees)
  context/           # project overview, architecture, conventions, taxonomy (retrieval tags)
  specs/             # requirement docs, architecture docs, tasks
  bugs/              # bug reports
  knowledge/         # assumptions/ (validated) and lessons/ (learned)
  templates/         # copies of artifact templates (from this toolkit)
  partials/          # copies of shared shell snippets (from this toolkit)
  workflows/         # copies of Dynamic Workflow scripts (from this toolkit)
  config.yml         # only if you opt into cross-repo coordination (or copy in a preset)
```

The toolkit repo contains the **process**; each code repo contains the **artifacts**. Skills read `.aif/config.yml` at runtime for anything project- or org-specific — `/init` creates it only when you opt into cross-repo coordination (otherwise copy it from a preset or the template). Cross-repo features (spanning api + web + worker) are supported via the `repos:` block.

## Everything else

- [`AGENTS.md`](AGENTS.md) — the agent-facing guide to this repo (layout, install, house rules) — readable by any AGENTS.md-aware tool; `CLAUDE.md` imports it
- [`skills/ETHOS.md`](skills/ETHOS.md) — the principles injected into every AIF skill
- [`examples/`](examples/) — how an org extends the toolkit (skill/agent skeletons, house rules)
- [`references/`](references/) — on-demand checklists; several are fill-in templates
- [`workspace-CLAUDE.md`](workspace-CLAUDE.md) — always-loaded workspace context, as a fill-in template
- [`tips.md`](tips.md) — Claude Code power-user guide
- [`skills/partials/`](skills/partials/) — shared POSIX shell functions (forge PR adapter for GitHub/Azure DevOps, id allocation, telemetry)
- [`skills/workflows/`](skills/workflows/) — deterministic Dynamic-Workflow scripts for `/sprint --workflow`
- [`tools/`](tools/) — the `aif` CLI, the skill linter, and the opt-in delegation CLIs
- [`skills/presets/`](skills/presets/) — stack-shaped starter configs for `.aif/config.yml`
- `./catalog.sh` — terminal inventory of every skill, agent, hook, and reference

## Updating

```bash
cd "$(readlink ~/.claude/skills)" && git pull
```

`git pull` applies once the toolkit is a published git repo with a remote (or your fork of it). Since `~/.claude/skills` is a symlink, changes are picked up immediately by every session.

## Contributing

New skills follow the toolkit conventions (`.aif/context/conventions.md`): POSIX-only shell in fences, two-level `.aif/` → `~/.claude/skills/` fallback for every asset, PR operations through the forge adapter, org values through config (never hardcoded), `python3 tools/lint-skills/check.py` clean. New agents get `tier:` frontmatter, an entry in `tools/aif/agents_render.py`, and an `aif agents render` run.

## License

MIT — see [`LICENSE`](LICENSE).
