---
name: using-aif
description: Discovers and routes to the right ai-factory skill, subagent, or MCP tool for the current task. Loaded automatically by the SessionStart hook in every repo where AIF is installed. Use when starting work, when unsure which tool to reach for, or when the work crosses service boundaries.
---

# Using ai-factory

The ai-factory toolkit is **knowledge + skills + subagents + hooks + MCP**, layered. This meta-skill is the routing table. It spans two skill families: the **AIF pipeline** (spec-driven lifecycle: `/spec` → `/architect` → `/proceed` → `/review` → `/wrapup`) and the **org workflow skills** (extensible-service modules, CRUD modules, shared-environment triage, capability specs).

## Layer cake

| Layer                             | Always loaded?                          | Cost                   | Best for                                                                                                        |
| --------------------------------- | --------------------------------------- | ---------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `workspace-CLAUDE.md`             | Yes (every session under the workspace) | Free, in context       | Service map, auth contract, multi-tenancy rules, daily commands                                                  |
| `references/*.md`                 | No — load on demand                     | Pay only when relevant | Detailed checklists (multi-tenancy, JWT, migration safety, MCP cheatsheet, commit prefixes, regression markers)  |
| Experts (`.aif/experts/*.md`)     | No — activate by path match             | Pay only in-domain     | Curated domain context (a framework, service, data store, product area), injected when a change touches its paths |
| Subagents (`agents/*.md`)         | No — invoke when task fits              | Own context window     | Audit / research / orchestration over multiple files or repos                                                    |
| Skills (`<skill>/SKILL.md`)       | No — invoke when task fits              | Choreographed steps    | Recurring multi-step workflows (spec a feature, run the pipeline, add a module, ship a PR, triage the dev env)   |
| Hooks (`hooks/*.sh`)              | Deterministic — fire on events          | Free                   | Formatters, secret scan, commit-prefix gate, precommit gate, session reflection                                  |
| MCP tools (`mcp__<namespace>__*`) | No — invoke when needed                 | Fast network call      | Live state — DB schema, k8s pods, traces, deployed config (`<namespace>` from `mcp.namespace` in `.aif/config.yml`) |

## Intent → tool

```
Task arrives
    │
    ├── "Work issue #N" / "implement this issue, ship it"          ──→ /from-issue
    │
    ├── AIF pipeline (spec-driven lifecycle):
    │   ├── "Set up .aif/ in a repo"                               ──→ /init
    │   ├── "Adopt the toolkit in an existing codebase"            ──→ /onboard
    │   ├── "Is the toolkit paying off? / baseline metrics"        ──→ /measure
    │   ├── "Write a spec for this feature request"                ──→ /spec
    │   ├── "Design + break spec into tasks"                       ──→ /architect
    │   ├── "Run the whole pipeline for REQ-xxx"                   ──→ /proceed
    │   ├── "Run several REQs in parallel"                         ──→ /sprint
    │   ├── "Gate-check a phase output"                            ──→ /validate
    │   ├── "Self-review before formal review"                     ──→ /reflect
    │   ├── "Multi-agent review of this change"                    ──→ /review
    │   ├── "Capture what someone working in <area> must know"     ──→ /expert
    │   ├── "Assume this artifact is wrong; prove it"              ──→ /adversary
    │   ├── "Fix this bug (report→fix→verify→ship)"                ──→ /bugfix
    │   ├── "Canary deploy with smoke tests"                       ──→ /canary
    │   ├── "Close out: commit, merge, deploy, artifacts"          ──→ /wrapup
    │   ├── "What AIF work is in flight?"                          ──→ /status (local) / /manifest (remote)
    │   ├── "Codebase health / API cost audit"                     ──→ /analyze, /optimize
    │   └── "Are this repo's .aif/ copies stale vs the toolkit?"   ──→ /template-drift
    │
    ├── "Starting a feature" / "What does the platform promise?"   ──→ /feature-prep
    ├── "Architectural change / new service / new contract"        ──→ /grill-feature
    │
    ├── "Add a module to an extensible service" / "New signal"     ──→ /add-detector
    ├── "Scaffold a CRUD module" / "New admin endpoint"            ──→ /new-admin-module
    │
    ├── "Implement this — multi-file"                              ──→ /incremental-implementation
    ├── "Verify against the contract / docs before coding"         ──→ /source-driven
    ├── "Something's broken — where do I start?"                   ──→ /debug
    ├── "Something's broken in the shared dev environment"         ──→ /triage-dev
    │
    ├── "Remove this old API / deprecate this field"               ──→ /deprecate
    ├── "Update dependencies / anything vulnerable?"               ──→ /dep-update
    ├── "Are our licenses clean? / build an SBOM"                  ──→ /license-audit
    ├── "What secrets are expiring? / rotate <credential>"         ──→ /rotate-secrets
    ├── "Clean up accumulated Claude permission grants"            ──→ /audit-permissions
    ├── "Are the docs stale after this change?"                    ──→ /doc-drift
    ├── "What shipped since <tag>? / draft release notes"          ──→ /release-notes
    ├── "Threat-model this spec before we build it"                ──→ /threat-model
    ├── "Commit / branch / what prefix?"                           ──→ /git-workflow
    ├── "Ready to merge — fan out the reviewers"                   ──→ /ship
    │
    ├── "Context is heavy / stepping away / handoff to teammate"   ──→ /handoff
    │
    ├── "What breaks if I change X across repos?"                  ──→ @cross-repo-impact
    ├── "Audit this auth/multi-tenancy code"                       ──→ @security-reviewer
    ├── "Is this policy correct?" (if your org uses Cedar)         ──→ @cedar-policy-reviewer
    ├── "Is this migration safe?"                                  ──→ @migration-analyzer
    ├── "Run the regression suite against my changes"              ──→ @kind-regression-runner
    ├── "Bring up the local stack"                                 ──→ @local-stack-runner
    ├── "Auto-fix CI on this PR"                                   ──→ @pr-shepherd
    ├── "Address the code-review bot's comments"                   ──→ @gemini-reviewer
    │
    └── Live state? → MCP tools (see ~/.claude/aif-references/mcp-tools-cheatsheet.md)
```

## When to use a reference vs. embedding the rule

Prefer a reference (`Read references/<file>.md`) over re-stating rules from memory when:

- Touching auth → `~/.claude/aif-references/jwt-checklist.md`
- Touching DB / cache / handler → `~/.claude/aif-references/multi-tenancy-checklist.md`
- Authoring or reviewing SQL migrations → `~/.claude/aif-references/migration-safety-checklist.md`
- About to commit → `~/.claude/aif-references/commit-prefix-check.md`
- Picking test markers → `~/.claude/aif-references/regression-markers.md`
- About to investigate live state → `~/.claude/aif-references/mcp-tools-cheatsheet.md`

## Operating rules

### 1. Surface assumptions

Before non-trivial work, state assumptions explicitly so the user can correct them:

```
ASSUMPTIONS:
1. <assumption about the spec / contract>
2. <assumption about scope>
→ Correct me now or I'll proceed.
```

### 2. Don't speculate when MCP can answer

If the question is "what's deployed in the shared dev environment?" / "what tables exist?" / "is the error rate spiking?" — that's an MCP call (`mcp__<namespace>__*`, namespace from `mcp.namespace`), not a guess. See `~/.claude/aif-references/mcp-tools-cheatsheet.md`.

If no MCP server is configured (`mcp.namespace` absent) or it's unreachable, **say so** and fall back to local alternatives — read the code, use `gh`, use kubectl if your environment can reach the cluster. Never fabricate live state.

### 3. Pick the smallest tool

- One file, one function → just edit
- Multi-file recurring workflow → skill
- Investigative or report-producing → subagent
- Cross-repo blast-radius → `@cross-repo-impact`

Don't reach for `/ship` on a one-line typo. Don't reach for a subagent when reading the file is enough.

### 4. Verification is non-negotiable

Every skill ends with a verification step. The work isn't done until you've produced evidence — a green build, a passing test, a query result, a working curl. "Looks right" is not done.

### 5. Hooks are deterministic — don't argue with them

If `commit-prefix-check.sh` blocks you, fix the subject. If `precommit-gate.sh` blocks you, fix the formatting. The hooks are pass/fail predicates and can't be talked out of. See `~/.claude/aif-references/commit-prefix-check.md`.

## Failure modes to avoid

1. Inventing auth patterns instead of reading `~/.claude/aif-references/jwt-checklist.md`
2. Writing a SQL query without filters on every key in `tenancy.keys` (from `.aif/config.yml`)
3. Speculating about deployed state when MCP can answer
4. Manually doing work a skill or subagent already automates
5. Skipping `/feature-prep` and discovering mid-implementation that the spec needed an entry first
6. Adding fine-grained tests to the org regression suite (`regression.repo`) instead of repo-local
7. Committing with a subject that fails the configured prefix gate (`org.commit_prefix_regex`; conventional commits if absent)
8. Using `WebFetch` for architecture docs that live in a local checkout (`org.adr_dir`, `org.spec_registry` — just `Read` them)

## Quick reference

Skills, partials, templates, workflows, and presets live under the repo's `skills/` directory, which is symlinked at `~/.claude/skills/`; agents, hooks, and references are top-level dirs with their own `~/.claude/` symlinks.

| Asset             | Path                                                 | Discover with                                        |
| ----------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| Subagents         | `agents/*.md`                                        | `/agents` in-session, or `./catalog.sh` from terminal |
| Skills            | `skills/<skill>/SKILL.md`                            | this skill's "Intent → tool" map, or `./catalog.sh`  |
| References        | `references/*.md`                                    | `references/README.md`                               |
| Hooks             | `hooks/*.sh`                                         | `README.md` § Hooks                                  |
| Workspace context | `workspace-CLAUDE.md` (= `<workspace>/CLAUDE.md`)    | always loaded                                        |
| MCP tools         | `mcp__<namespace>__*` (config key `mcp.namespace`)   | `~/.claude/aif-references/mcp-tools-cheatsheet.md`                 |
