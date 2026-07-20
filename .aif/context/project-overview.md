# Project Overview — ai-factory

## What this project is

ai-factory is an opinionated, general-purpose Claude Code toolkit: **skills, agents, hooks, references, and templates** in one repo, symlinked live into every Claude Code session on the machine. Any org can clone it and adopt it as their engineering starting point. It merges two lineages:

1. **The AIF pipeline** — a spec-driven development lifecycle (`/spec`, `/architect`, `/validate`, `/proceed`, `/sprint`, `/review`, `/adversary`, `/bugfix`, `/wrapup`, …) with a review-agent bench, deterministic Dynamic-Workflow orchestration, and the `aif` health CLI. Adapted from the MIT-licensed [adlc-toolkit](https://github.com/atelier-fashion/adlc-toolkit) (attribution in `LICENSE`).
2. **The org-workflow layer** — day-to-day engineering skills (`/from-issue`, `/ship`, `/debug`, `/git-workflow`, `/handoff`, `/triage-dev`, …), platform agents (security-reviewer, cross-repo-impact, migration-analyzer, pr-shepherd, …), deterministic hooks (formatters, secret scan, commit-prefix gate, precommit gate), and on-demand reference checklists. Everything org-specific is parameterized through `.aif/config.yml` (the `org:`, `environments:`, `mcp:`, `local_stack:`, `regression:`, and `tenancy:` sections) with stated graceful degradation when a key is absent.

This repo will dogfood the AIF pipeline on its own feature work: REQs will be tracked in `.aif/specs/` (starting from REQ-001), lessons in `.aif/knowledge/lessons/`, bugs in `.aif/bugs/`. It does not carry a vendored `.aif/templates/` — the canonical `skills/templates/` is what `/init` copies into consumer projects.

## Who uses it

- **Adopting engineers**: clone once, run `./install.sh`. The repo becomes `~/.claude/skills/` (and `agents/`, `aif-hooks/`, `aif-bin/`, `aif-references/` via sibling symlinks). Any improvement committed here is immediately visible to every Claude Code session on the machine — no publish step.
- **Toolkit maintainers** evolve the skills, agents, and hooks, and distribute the shared `.claude/settings.json` to the org's repos via `tools/fleet/distribute-settings.sh` + `tools/fleet/open-settings-prs.sh` (repo set controlled by `AIF_REPO_GLOB`).
- **Forking orgs** specialize the parameterized pieces: fill `workspace-CLAUDE.md`, complete the fill-in references, set the `org:` config keys, and (optionally) add org-specific skills/agents per `examples/`.

## Install model

Symlink-based live install. One canonical git clone on disk, symlinked at `~/.claude/skills/`. Edits to the clone are visible immediately. No separate installed copy, no sync step, no versioning at the install layer. `aif doctor` diagnoses every install dependency and prints a copy-pasteable fix for each failure.

## Primary surface areas

| Surface | Files | Purpose |
|---|---|---|
| Skills | `skills/<skill-name>/SKILL.md` | Markdown files invoked by Claude Code as slash commands (AIF pipeline + org-workflow families) |
| Agents | `agents/<agent-name>.md` | Specialized subagent definitions with tool restrictions and tier-based model selection (`aif agents render`) |
| Hooks | `hooks/*.sh` | Deterministic gates and formatters wired through each repo's `.claude/settings.json` |
| References | `references/*.md` | On-demand checklists — several are fill-in templates an adopting org completes |
| Templates | `templates/*` | Canonical templates for requirements, bugs, lessons, tasks, config, settings |
| Partials | `partials/*.sh` | Shared POSIX shell functions sourced by skills (forge adapter, id allocation, telemetry) |
| Workflows | `workflows/*.workflow.js` | Deterministic Dynamic-Workflow scripts (`/sprint --workflow`) |
| Ethos | `ETHOS.md` | The principles injected into every AIF skill |
| Workspace context | `workspace-CLAUDE.md` | Fill-in platform-context template, symlinked to `<workspace>/CLAUDE.md` |
| Examples | `examples/` | How an org extends the toolkit with its own skills/agents |

## Relationship to consumer projects

`/init` is the bridge: it creates `.aif/context/`, `.aif/specs/`, `.aif/bugs/`, `.aif/knowledge/`, `.aif/templates/`, and `.aif/workflows/` in a consumer repo, copying from the toolkit's root directories. After `/init`, the consumer project's skills read from **its** `.aif/` structure — not the toolkit's. Hooks are wired separately, through the shared `.claude/settings.json` distributed to each repo.

## REQ-numbering policy (remote-derived, collision-safe)

Numbering is **remote-derived**: a new id is `max(local-cache, remote-high-water) + 1`, computed by `partials/id-alloc.sh` (allocation) and rechecked at push/PR time by `partials/id-recheck.sh`. The remote is the source of truth; the per-machine `~/.claude/.global-next-req` counter is a fast-forwarded *cache*, not the authority. The same pattern allocates BUG ids (`~/.claude/.global-next-bug`) and LESSON ids (`~/.claude/.global-next-lesson`). This repo starts its own numbering from REQ-001.
