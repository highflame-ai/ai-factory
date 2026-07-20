---
name: handoff
description: Compact the current session into a handoff document so a fresh agent (or you, after `/clear`) can pick up the work without losing context. Captures per-repo branch state across every repo touched (per `.aif/config.yml` `repos:`), in-flight PRs, MCP queries worth replaying, spec-registry entries in motion, and assumptions made. Use when context is getting heavy, before `/clear`, when stepping away from work that spans multiple repos, or when explicitly asked to "hand this off" / "summarize for next session" / "write a handoff".
argument-hint: "What will the next session focus on? (optional)"
---

# Handoff — compact a session for the next agent

## Overview

Multi-repo sessions routinely cross 3–4 repos at once (e.g. api migration → worker contract change → web call site → dashboard signal). A summary that says "I worked on auth" loses everything that matters: which branch in which repo, which spec entry is mid-flight, which MCP query showed the bug, which assumption we made and never validated. This skill writes a document a fresh agent can read in 60 seconds and resume from.

## When to use

- Context is getting heavy and `/clear` is near
- Stepping away from work that spans ≥2 repos
- Switching from one feature to another and want to come back later
- About to hand the session to a different teammate
- User says "handoff", "summarize for next session", "write me a handoff doc"

**Skip** for: single-file edits, sessions where only one repo was touched and the PR is open (the PR description IS the handoff), trivial Q&A sessions with no code changes.

## What to capture (and what NOT to)

The doc is a **delta against the codebase + open PRs**, not a re-statement of them. Reference, don't duplicate.

| Capture                                                                 | Skip (link instead)                          |
| ----------------------------------------------------------------------- | -------------------------------------------- |
| Per-repo `git status` + branch + commits-ahead                          | Full diff (it's in `git diff`)               |
| In-flight PRs by URL + their current CI state                           | PR description content                       |
| Spec-registry entries proposed / in motion (IDs, status)                | Full spec-registry file content              |
| MCP queries that were load-bearing (the exact call + the answer to it)  | Routine MCP exploration with no insight      |
| Assumptions made and NOT validated                                      | Validated facts (those are in the code now)  |
| Open questions / things blocked                                         | Things already decided + acted on            |
| Suggested next skill(s) to invoke on resume                             | Generic "next steps" prose                   |
| The user's goal in one sentence (what does "done" look like?)           | Long preamble                                |

**Never include** in the handoff:

- API keys, JWT private keys, cloud credential JSON, local env-file contents, internal service secrets
- Anything from local env files (`.env`, compose/dotenv files), `keys/` directories, or credential JSON files
- Full output of MCP observability / DB / k8s queries (link the call, summarize the answer in one line)

If you see secrets in tool output, the rule is: **summarize what they implied, never paste them**.

## Process

### Step 1 — Resolve where the doc goes

Resolve the path in shell first so `$TMPDIR` actually expands (Write/Edit tools take a literal path and won't run shell expansion):

```bash
out="$(printf '%s/handoff-%s-%s.md' "${TMPDIR:-/tmp}" "<slug>" "$(date +%Y%m%d-%H%M)")"
echo "$out"   # use this resolved path when calling Write
```

Example resolved path: `/tmp/handoff-billing-refactor-20260527-1542.md` (or `/var/folders/.../T/handoff-...md` on macOS where `$TMPDIR` is per-user).

`<slug>` = 2–4 kebab-cased words capturing the work (the user's argument trumps your guess if they passed one).

Do NOT write inside the workspace — handoff docs aren't checked in.

### Step 2 — Walk the repo surface

Run these in parallel (one Bash call each):

```bash
# Repos touched this session — derive from your conversation, not from a global scan.
# For each touched repo (cd <repo>):
git -C <repo> status --short --branch
git -C <repo> log --oneline @{u}.. 2>/dev/null   # commits ahead of remote
git -C <repo> stash list
```

```bash
# Open PRs authored by current user across the org (NOT just cwd repo —
# repo-scoped PR listing only covers the current repo; `gh search prs` queries org-wide).
# Owner comes from .aif/config.yml org.github_org; if unset, fall back to this
# repo's origin owner: owner="$(gh repo view --json owner -q .owner.login)"
gh search prs --owner "<owner>" --author "@me" --state open --limit 20 \
  --json url,title,repository,state
```

```bash
# Spec-registry entries in motion (planned vs implemented) — only if
# org.spec_registry is configured AND that file was touched this session.
# Skip silently otherwise.
grep -nE "status:\s*(planned|proposed)" <org.spec_registry path> | head -20
```

For MCP queries: scan the conversation for `mcp__<namespace>__*` calls (`<namespace>` from `.aif/config.yml` `mcp.namespace`) and pick the ones whose result influenced a decision. A query that returned "0 rows, table doesn't exist" matters; one that returned the expected value and was never referenced again doesn't. If no MCP server is configured, there's nothing to scan — omit that section of the doc.

### Step 3 — Write the doc

Use this template verbatim — the structure is the contract a resumer relies on:

```markdown
# Handoff: <one-line description of the work>

**Generated**: <ISO timestamp>
**Goal**: <one sentence — what does "done" look like?>
**Next session should**: <one sentence the user passed, or your best inference>

## Current state by repo

### <repo-name> — branch `<branch>` (<N> ahead of remote)
- **Open PR**: <url> — CI: <state>  *(omit line if none)*
- **Uncommitted**: <one-line summary, e.g. "3 files modified in internal/policy/">
- **Last commit**: `<short SHA> <subject>`
- **What's left here**: <one sentence>

*(repeat per touched repo — order by where the next session will pick up first)*

## Capability spec status

- `<ENTRY-ID>` — <status> — <one-line description> — <where it stands: PR open / drafted / accepted>
- *(omit section if no spec entries are in motion — always omit when org.spec_registry is unset)*

## Load-bearing MCP findings

- **`<tool_name>(<args>)`** → <one-line answer that mattered>
- *(omit section if no MCP query influenced the work, or no MCP server is configured)*

## Assumptions made and NOT validated

1. <assumption>. *Validate by: <how>*
2. *(...)*

*(omit section if every assumption was validated in the session)*

## Open questions / blockers

- <question or blocker>. *Where it surfaced: <repo>:<file>*

*(omit section if nothing is open)*

## Suggested skills to invoke on resume

- `/<skill>` — <why>
- *(usually 1–3; pick from the workspace `using-aif` intent map)*

## Out of scope / explicitly deferred

- <thing the user asked NOT to touch, or thing we noticed but decided to skip>

*(omit section if nothing was deferred)*
```

Empty sections get omitted entirely — don't write "N/A" rows. A clean handoff for narrow work is two repos and three lines per section, not boilerplate.

### Step 4 — Tell the user

After writing, output exactly:

```
Handoff written: <absolute path>
Resume in a fresh session with:
  cat <absolute path>
```

If the next session is going to a different teammate, also remind: "Open PRs are listed in the doc — they have full context that doesn't need to be repeated."

## Multi-repo gotchas

- **Multi-tenancy state**: if the session touched tenant-scoped flows (see `tenancy.keys` in `.aif/config.yml`), the handoff MUST note which tenant-key values were used for testing (e.g. which `account_id`+`project_id` pair). The next session will hit "no data" mysteries otherwise. Skip if `tenancy:` is unset.
- **Local env drift**: if you changed any local env var to make something work, capture *which var changed and to what kind of value* — never the value itself if secret. Example: "Set `BILLING_API_KEY` to a working key in the local env file" (not the key).
- **Cross-repo PR dependencies**: if the api PR depends on the spec PR landing first, say so in the order of the "Current state by repo" section AND in "Open questions".
- **Spec entry mid-flight**: if `feature-prep` produced a `NEW_ENTRY` with `status: planned` and the verifying regression test hasn't landed, list it under "Capability spec status" — the promotion rule fails otherwise. (Only applies when `org.spec_registry` is configured.)
- **In-progress git merge**: if any repo has unresolved merge conflicts (check `git status` for "All conflicts fixed but you are still merging" or unmerged files), call it out at the TOP of the affected repo's section. A fresh agent committing on top of an unresolved merge is a real hazard.

## Rationalizations (and rebuttals)

| You'll be tempted to think…                          | Why it's wrong                                                                                                              |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| "I'll just summarize what I did"                     | A history summary doesn't help the next session — they care about state, not narrative. Capture state.                      |
| "I'll dump the full git diff so they have context"   | They can run `git diff`. The handoff is the *frame* around the diff, not a copy.                                            |
| "I'll skip the MCP findings — they can re-query"     | Re-running an observability query costs time and the result may have changed. Capture the answer that mattered.             |
| "I'll just write it in the workspace as `HANDOFF.md`"| It'll get committed by accident or pollute git status. Use `$TMPDIR`.                                                       |
| "Secrets are fine, it's local"                       | The doc gets pasted, shared, screenshotted. Never include secrets.                                                          |
| "The user didn't pass an argument so I can't slug it"| Infer from the work. "billing-refactor" is fine without explicit input.                                                     |

## Red flags

- Doc longer than ~200 lines → you're duplicating diffs or PR descriptions. Reference them.
- "Current state by repo" section lists repos you only read, not modified. Drop them; they're not part of the state to resume.
- "Assumptions made" section is empty AND the work was multi-step. You almost certainly made assumptions — surface them.
- A spec-registry entry is in motion and not mentioned. The next session will rediscover it the hard way.
- You wrote the doc inside the workspace. Move it to `$TMPDIR`.

## Verification

Done when:

- [ ] Doc exists at `${TMPDIR:-/tmp}/handoff-<slug>-<timestamp>.md`
- [ ] Every touched repo appears under "Current state by repo" with branch + commits-ahead
- [ ] Every open PR is linked with CI state
- [ ] Any `NEW_ENTRY` / `EDIT_EXISTING` spec-registry work appears (when `org.spec_registry` is configured)
- [ ] No secrets in the doc (grep for `sk-`, `AKIA`, `BEGIN PRIVATE KEY`, env-file or credential-JSON content before finishing)
- [ ] "Suggested skills to invoke on resume" names ≥1 concrete skill
- [ ] Final message to the user contains the absolute path and resume command

## Anti-patterns

- Writing prose history instead of capturing state
- Duplicating PR descriptions or `git diff` output
- Including secrets, even by accident in pasted MCP/k8s output
- Saving inside the workspace
- Listing every repo touched, including read-only browsing
- Skipping "Suggested skills" — that's the lever that makes resume fast
- Writing a handoff for trivial single-file work — overhead beats value
