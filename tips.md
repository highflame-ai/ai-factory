# Claude Code — Power-User Tips

Everything here is about getting more out of your Claude Code session with less effort. Skim once, apply forever.

If you want the canonical Anthropic guidance, see the sources at the bottom. This doc is the opinionated filter for teams using this toolkit.

---

## The four modes (Shift+Tab)

Press **Shift+Tab** to cycle through permission modes. The mode shows in the status line.

| Mode | What it does | When to use |
|------|-------------|-------------|
| **default** | Prompts for every Edit, Write, Bash command | New sessions, unfamiliar work, first run of a prompt |
| **auto-accept edits** | Auto-approves Edit and Write; still prompts for Bash | 90% of active coding — trust Claude with files, keep bash prompts for safety |
| **plan mode** | Read-only. Claude can research, read files, propose a plan — but cannot edit | Non-trivial tasks: always start here, review the plan, then exit to code |
| **bypass permissions** | All tools auto-approved, including Bash — no prompts at all | Sandboxed/containerized environments only; never on a machine with credentials you care about |

**Rule of thumb**: Start every non-trivial task in plan mode. Review what Claude proposes. Exit to auto-accept and let it run.

---

## Discovering what team-specific tooling you have

At any point, three ways to see what subagents + skills are active:

| Where | Command |
|-------|---------|
| **In session** | `/agents` — built-in Claude Code command, lists active subagents |
| **From terminal** | `<workspace>/ai-factory/catalog.sh` — full inventory with examples |
| **Quick peek** | `ls ~/.claude/agents/` and `ls ~/.claude/skills/` |

To see a specific agent's full system prompt: `cat ~/.claude/agents/<name>.md`
To see a skill's recipe: `cat ~/.claude/skills/<name>/SKILL.md`

### Invoking subagents (three equivalent ways)

```
By name:          "Have the security-reviewer audit this PR."
@-mention:        "@security-reviewer audit this PR."
Natural language: "Check this PR for multi-tenancy violations."
```

Natural language works because Claude reads each subagent's `description:` frontmatter and picks the best fit. If you want a specific one, name it.

### Invoking skills (two equivalent ways)

```
Slash command:    /feature-prep
Natural language: "I'm about to start a new feature — help me scope it."
```

---

## /commands cheatsheet

Run in the chat:

| Command | What it does |
|---------|-------------|
| `/clear` | Wipe context. Use between unrelated tasks — context degrades as it fills. |
| `/compact` | Summarize old context to free space without losing the thread. |
| `/model` | Switch model mid-session (Opus ↔ Sonnet ↔ Haiku). |
| `/resume` | Resume a previous session. |
| `/agents` | Manage subagents (list, create, edit). |
| `/permissions` | Edit the allow/deny list for tools. Persists to `.claude/settings.local.json`. |
| `/init` | Bootstrap the `.aif/` structure in the current repo — this toolkit's skill (it shadows Claude Code's built-in `/init`, which generates a CLAUDE.md). |
| `/help` | Full command list. |
| `/fast` | Toggle fast mode (Opus 4.6 only — not Opus 4.7, as of early 2026). |

**Use `/clear` aggressively.** Heuristic: if Claude has failed at the same thing twice, or you're about to switch domains, `/clear` and re-scope. A clean session with a better prompt beats a cluttered session every time.

---

## Opus 4.7 — effort levels

(Model names and behaviors here are as of early 2026 — check `/model` for what's current.)

Opus 4.7 exposes explicit effort (you set this at invocation / in settings, depending on your client):

| Effort | Token cost | Use for |
|--------|-----------|---------|
| `low` | Cheapest | One-shot lookups, simple refactors, "find X in the codebase" |
| `medium` | Balanced | Default for general work |
| `high` | Expensive | Research, multi-file changes |
| `xhigh` | Very expensive | **Default for platform coding.** Complex multi-repo work, cross-service contract design, policy authoring |
| `max` | Maximum | Security review, migration planning, anything where a wrong answer is expensive |

**Opus 4.7 interprets instructions more literally than 4.6.** If you say "just fix the bug, don't refactor", it actually stops at the bug. Use this — tell it exactly what scope you want.

---

## Prompting patterns that actually work

### 1. Reference files with `@path/to/file`

Don't describe where code lives. Reference it:

```
✅ Take a look at @api/internal/billing/invoice.go and add a new context field for overdue_notified.

❌ There's a billing file in the api repo, I think it's somewhere in internal/billing...
```

Saves tokens, eliminates ambiguity, avoids "Claude reads 40 wrong files first."

### 2. Delegate to subagents by name

```
Have the security-reviewer audit this change.

Can cross-repo-impact tell me what breaks if I rename this shared field?
```

Subagents run in their own context window. They return a summary. Your main session stays clean.

### 3. Paste screenshots for UI work

When debugging web UI: screenshot the broken state, paste it into the chat. Claude reads images and can map pixels to code. Don't describe — show.

### 4. Structure complex prompts

For anything non-trivial, use this skeleton:

```
## Context
[What's the current state of the code / what I've tried / what I know doesn't work]

## Goal
[What the end state should be]

## Constraints
- Must not break [X]
- Must preserve [Y]
- Use the existing pattern in @path/to/reference.go

## Done criteria
- [ ] Tests pass (go test ./... in the api repo)
- [ ] No new lint warnings
- [ ] API docs regenerated if handler signatures changed
```

Claude works much better with explicit done-criteria than "fix it."

### 5. Let Claude verify its own work

The single biggest quality lever: tell Claude how to check its output.

- "After each edit, run `go vet ./...` and fix any failures before continuing."
- "Start the dev server and click through the flow — confirm the toast actually appears."
- "Compare your output against @docs/expected-schema.json."

Without a verification step, you become the only feedback loop. Painful and slow.

---

## Context management

The 1M context window is a trap if you fill it with junk. Claude's output quality **degrades** as context fills past ~200k tokens, regardless of window size.

### The hierarchy

1. **Main session (20–50k tokens)**: only the code you're actively editing
2. **Subagents**: delegate "investigate X" — they return a summary, cluttering their context not yours
3. **`/clear`**: reset between unrelated tasks
4. **`/compact`**: summarize old work when you want to continue but free up tokens

### Signs you need to reset

- Claude keeps re-reading files it already read
- It starts re-asking questions you answered 20 messages ago
- It contradicts earlier decisions
- Output quality visibly drops

Hit `/clear` or `/compact` and start with a fresh, well-scoped prompt.

---

## Git worktrees — parallel Claude sessions

Boris Cherny (creator of Claude Code) calls this his #1 productivity unlock. For large migrations or multi-repo changes:

```bash
# Main branch (<workspace> = your workspace root: AIF_WORKSPACE env →
# ~/.claude/aif/config.yml workspace.root → the toolkit clone's parent dir)
cd <workspace>/api

# Spin up a worktree on a feature branch
git worktree add ../api-identity-migration feature/identity-migration
cd ../api-identity-migration
claude    # new session, isolated context, working on the feature

# Meanwhile in another terminal:
cd <workspace>/api
claude    # keep working on main branch with a second session
```

Concrete example — a large data-model migration:
- Worktree 1 in `api-migration-analysis` → analyzing source data
- Worktree 2 in `api-migration-write` → writing the migration SQL
- Worktree 3 in `web-migration-consumer` → updating frontend consumers

Three parallel streams, three isolated Claude sessions. Converge when ready.

**Clean up:** `git worktree remove ../path` when done.

---

## Headless mode — `claude -p`

Run Claude non-interactively for CI / scripts / batch work:

```bash
# One-shot prompt, stream text output
claude -p "Review this PR for multi-tenancy violations"

# Structured JSON output for piping into tools
claude -p "Extract all exported functions in this file" --output-format json

# Restrict tool access
claude -p "..." --allowedTools Read,Grep
```

Ideas:
- **PR gate** in CI: run security-reviewer on every PR touching auth or tenancy code
- **Drift check**: nightly run that checks if schemas changed without regenerating downstream packages
- **Commit gate**: a pre-commit hook that checks subjects against your `org.commit_prefix_regex` (this toolkit ships one: `hooks/commit-prefix-check.sh`)
- **Migration safety**: pre-commit hook that runs migration-analyzer on any SQL file in `migrations/`

---

## Getting unstuck — the confused-Claude playbook

When Claude is spinning, wrong, or stuck:

1. **Don't pile on more context.** Clarifications rarely rescue a confused session.
2. **`/clear`** and re-ask with a sharper prompt.
3. **Drop into plan mode** (Shift+Tab twice from auto-accept) and have Claude articulate its understanding before doing anything.
4. **Delegate to a subagent** with a narrow brief: "you only need to answer X" — cleaner context, focused output.
5. **Give it a reference.** Point at a file that already solves the problem correctly elsewhere: "do it like @path/to/working-example.go."
6. **Try a different model.** `/model` to switch to Sonnet for certain kinds of "just apply this pattern" tasks — sometimes faster and cheaper.

---

## The 10 rules

Short list — if you internalize only these, 80% of the value:

1. **Plan Mode for anything non-trivial.** Shift+Tab twice.
2. **Auto-accept edits for active coding.** Shift+Tab once.
3. **`/clear` between unrelated tasks.** Don't accumulate.
4. **Delegate research to subagents.** `security-reviewer`, `cross-repo-impact`, etc. Keep main context lean.
5. **`@file` references over prose descriptions.** Point, don't describe.
6. **Verification steps in every prompt.** "After editing, run X and confirm Y."
7. **Worktrees for parallel work.** 2-3 streams is a sweet spot.
8. **`xhigh` effort for platform coding, `max` for security/migration work.**
9. **Screenshots for UI.** Never describe; show.
10. **When stuck, `/clear` + sharper prompt.** Don't pile on.

---

## Sources

- [Anthropic — Claude Code Best Practices](https://code.claude.com/docs/en/best-practices.md)
- [Anthropic — Session Management and 1M Context](https://claude.com/blog/using-claude-code-session-management-and-1m-context)
- [Anthropic — Subagents](https://code.claude.com/docs/en/sub-agents)
- [Anthropic — Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- [Boris Cherny — How Boris Uses Claude Code](https://howborisusesclaudecode.com/)
- [Every.to — Claude Code with Boris & Cat](https://every.to/podcast/how-to-use-claude-code-like-the-people-who-built-it)
