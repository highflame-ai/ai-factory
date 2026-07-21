# ai-factory — agent guide

ai-factory is an opinionated toolkit for AI-assisted software engineering: skills (multi-step workflows), agents (scoped subagent definitions), deterministic hooks, reference checklists, and a role-based capability model compiled to multiple agent runtimes. Claude Code is the native runtime; Codex/Copilot/Cedar consume the compiled outputs under `compiled/`.

## Layout

```
skills/           41 skills (<name>/SKILL.md) + partials/ templates/ workflows/ presets/ ETHOS.md
agents/           26 subagent definitions (frontmatter: tier -> role, tools, rendered model)
roles/            capability model — single source of truth for what each agent role may do
compiled/         GENERATED from roles/ by `aif compile` — never hand-edit
hooks/            deterministic gates (formatters, secret scan, commit-prefix, precommit, reflection)
references/       on-demand checklists; several are fill-in templates
tools/            aif CLI (doctor/compile/agents render/renumber), skill linter, fleet scripts, delegation
examples/         how an org extends the toolkit (skill/agent skeletons)
```

## Installing (when asked to set this toolkit up)

```bash
./install.sh              # idempotent; symlinks ~/.claude/skills -> <repo>/skills,
                          # ~/.claude/agents, ~/.claude/aif-{hooks,bin,references},
                          # <workspace>/CLAUDE.md; writes the `aif` shim; ends with `aif doctor`
aif doctor                # the answer to every "is my environment right?" question —
                          # each FAIL prints a copy-pasteable fix
```

Then, per code repo: run `/init` in a Claude Code session to bootstrap its `.aif/` structure, and fill `.aif/config.yml` (the `org:`/`environments:`/`mcp:`/`local_stack:`/`regression:`/`tenancy:`/`secrets:` sections drive the org-workflow skills; every skill states its graceful degradation when a key is absent).

## Using

- **Claude Code**: skills are slash commands (`/spec`, `/proceed`, `/review`, `/ship`, …). `/using-aif` is the routing table and is auto-injected at SessionStart once hooks are wired. `./catalog.sh` prints the full inventory.
- **Headless/CI**: see `references/trigger-recipes.md`; run with the least-privilege role overlay: `claude --settings compiled/claude/settings-<role>.json -p "..."`.
- **Codex**: merge `compiled/codex/config.toml` profiles; `codex --profile reviewer`.
- **Copilot**: paste `compiled/copilot/copilot-instructions-roles.md` into `.github/copilot-instructions.md`.
- **Cedar gateway** (optional): load `compiled/cedar/` schema + policies.

## House rules when editing THIS repo

- Skills: POSIX-only shell inside ```sh fences; two-level asset fallback (`.aif/<asset>` then `~/.claude/skills/<asset>`); PR operations only via the forge adapter (`skills/partials/forge.sh`, `aif_forge_pr_*`); org-specific values only via `.aif/config.yml` keys with stated degradation; no bare `$<digit>`.
- Agents: `tier:` picks the role; `tools:` must stay within `roles/<tier>.yaml`'s envelope (exceptions are declared in the role file with a reason, never quietly in frontmatter). Never hand-edit `model:` — run `aif agents render`.
- Roles: edit `roles/*.yaml`, then `aif compile` to regenerate `compiled/`.
- Full details: `.aif/context/conventions.md`.

## Verify before committing

```bash
python3 tools/aif/aif.py check          # runs ALL gates (CI + pre-commit call this)
python3 tools/aif/aif.py check --quick  # stdlib gates only (fast, pre-commit default)
```

`check` composes: the skill linter, `compile --check` (role envelopes + `compiled/` drift), `agents render --check` (model drift), and the Python/shell/node test suites.
