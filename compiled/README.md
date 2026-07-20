# compiled/ — generated capability configs (do not hand-edit)

Everything here is emitted by `aif compile` from [`roles/*.yaml`](../roles/).
Edit the role files, re-run `aif compile`; `aif compile --check` fails CI when
these are stale.

| File | Consumed by | How to adopt |
|---|---|---|
| `claude/settings-<role>.json` | headless/CI/sandboxed Claude Code sessions | `claude --settings compiled/claude/settings-reviewer.json -p "/review ..."`, or copy into the sandbox checkout's `.claude/settings.json` — enforces the role envelope at the harness level |
| `codex/config.toml` | OpenAI Codex CLI | merge the `[profiles.*]` blocks into `~/.codex/config.toml`, then `codex --profile reviewer` etc. |
| `copilot/copilot-instructions-roles.md` | GitHub Copilot | paste (or link) the block into your repo's `.github/copilot-instructions.md` — convention, not enforcement |
| `cedar/roles.cedarschema` + `cedar/roles.cedar` | a Cedar-based enforcement gateway | load schema + policies into your policy store; map agent identities to `Agent::"<name>"` principals in `Role::"<tier>"` groups |

For interactive Claude Code sessions, the repo's `agents/*.md` frontmatter *is* the native emission (validated by `aif compile --check`); the `claude/settings-*.json` overlays cover the headless/CI case where frontmatter alone can't constrain the session.
