# roles/ — the single source of truth for agent capabilities

Each `*.yaml` here defines one agent role's **capability envelope** — the
maximum set of powers any agent of that role may hold. Declare it once; `aif
compile` emits it everywhere:

| Target | What gets emitted | Enforcement strength |
|---|---|---|
| **claude** | validation of `agents/*.md` `tools:` frontmatter — every agent must stay ⊆ its role's envelope (+ declared exceptions) | hard (Claude Code enforces the tools list) |
| **claude (headless)** | `compiled/claude/settings-<role>.json` — permission overlays for CI/cron/sandboxed sessions (`claude --settings …`) | hard (harness permission rules) |
| **codex** | `compiled/codex/config.toml` — one profile per role (read-only vs workspace-write sandbox, network flag) | hard (sandbox) |
| **copilot** | `compiled/copilot/copilot-instructions-roles.md` — paste-in role boundaries | convention only (Copilot has no per-role enforcement surface; the block says so) |
| **cedar** | `compiled/cedar/roles.cedarschema` + `roles.cedar` — permit/forbid policies per role | hard, at a gateway — for orgs with an enforcement layer |

## Semantics

- **Envelope, not exact-match**: the role is the permission *boundary* (like a
  Cedar policy). An agent may declare any subset in its frontmatter; it may
  never exceed the envelope.
- **Exceptions are loud**: an agent that genuinely needs more than its role
  declares it here — in the role file, with a `reason:` — never quietly in its
  own frontmatter. `aif compile --check` fails on undeclared exceedance. The
  fleet currently carries exactly one exception (gemini-reviewer writes,
  because it applies accepted review-bot comments).
- **`envelope: all`** (implementer, orchestrator) means the boundary is
  something other than the toolset — the worktree, the pipeline contract.
- **`network:` is three-valued** — `false` (none), `read-only` (fetching
  context/dependencies: `gh pr view`, `gh search code`, package downloads —
  never posting), `true` (may post: forge PRs, MCP channels). MCP tools in an
  agent's frontmatter require `network: true` on its role. Cedar emits this
  as distinct `NetworkRead`/`NetworkWrite` actions; Codex and Copilot get the
  closest honest mapping their config surface allows.

## Workflow

```bash
$EDITOR roles/reviewer.yaml       # change a role or add an exception
aif compile                       # regenerate compiled/ + validate agents
aif compile --check               # CI/pre-commit: fail on drift or violations
```

Adding an agent? Its `tier:` picks the role; `aif compile --check` (and the
test suite) will tell you if its `tools:` exceed the envelope. Adding a role?
New yaml here + add the tier to `agents_render.py`'s classes.

File format: a constrained YAML subset (flat scalars, one `envelope:` list or
`all`, two-level `exceptions:` with inline `add: [..]` lists). The parser in
`tools/aif/compile.py` fails loud on anything fancier — no anchors, no
multiline strings.
