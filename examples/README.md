# Extending ai-factory

The toolkit ships two layers: the **AIF pipeline** (spec-driven lifecycle — generic, don't fork it, configure it) and the **org-workflow layer** (skills/agents parameterized through `.aif/config.yml`). This directory shows the third layer you add yourself: **skills and agents that encode your org's own patterns**.

## What to customize after cloning

1. **`.aif/config.yml` in each consumer repo** — copy `skills/templates/config-template.yml`, fill the `org:`, `environments:`, `mcp:`, `local_stack:`, `regression:`, and `tenancy:` sections. Every org-workflow skill states what it does when a key is absent, so fill only what you have.
2. **`workspace-CLAUDE.md`** — the fill-in platform-context template symlinked to `<workspace>/CLAUDE.md`. This is your always-loaded service map, auth contract, and conventions.
3. **Fill-in references** — `references/mcp-tools-cheatsheet.md`, `references/regression-markers.md`, `references/known-warts.md`, and the tenancy/JWT checklists are templates: complete them with your platform's specifics.
4. **Hook configuration** — `org.commit_prefix_regex` (or `AIF_COMMIT_PREFIX_REGEX`) to mirror your CI's commit gate; add your key prefixes to `hooks/secret-scan.sh`.
5. **Org-specific skills and agents** — the skeletons in this directory.

## Adding an org skill

Copy `org-skill-skeleton/` into `skills/` under your skill's name (`skills/<name>/SKILL.md` directories are what Claude Code discovers — `~/.claude/skills` symlinks the `skills/` directory):

```bash
cp -R examples/org-skill-skeleton skills/my-deploy-runbook
$EDITOR skills/my-deploy-runbook/SKILL.md
python3 tools/lint-skills/check.py     # must pass before committing
```

House rules (enforced by `tools/lint-skills`, documented in `.aif/context/conventions.md`):

- POSIX-only shell inside ```sh fences (no `local`, no bashisms); ```bash fences may use bash.
- Any PR operation goes through the forge adapter (`partials/forge.sh`, `aif_forge_pr_*`) — never direct `gh pr <op>`.
- Reference shared assets with the two-level fallback: `.aif/<asset>` first, `~/.claude/skills/<asset>` second.
- No bare `$<digit>` tokens (Skill-tool argument substitution hazard).
- Two good existing models to imitate: `/add-detector` and `/new-admin-module` — both are template skills that scaffold a module following a documented org pattern.

## Adding an org agent

Copy `org-agent-skeleton.md` into `agents/<your-agent>.md`, then register it:

1. Frontmatter needs `name`, `description`, `tier` (one of `reviewer|scanner|explorer|implementer|orchestrator`), and `tools` (or `effort` for heavy orchestrators). Do not hand-write `model:` — it is rendered.
2. Add the agent to `_SHIPPED_DEFAULTS` in `tools/aif/agents_render.py` with its `(tier, model)` pair.
3. Run `aif agents render` — it stamps the `model:` line; `tools/lint-skills` fails on drift.

## Keeping your fork current

Treat this repo as your canonical toolkit clone. If you forked from the public ai-factory, pull upstream improvements with a regular `git merge` — org-specific content lives in config, `workspace-CLAUDE.md`, the fill-in references, and your own skills/agents, so merges stay small.
