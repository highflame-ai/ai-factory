---
name: doc-drift
description: Find and fix documentation made stale by a code change — derive the changed public surfaces (APIs, CLI flags, config keys, env vars, endpoints) from a diff, hunt every doc that mentions them, classify stale vs missing coverage, and apply the doc updates. Use after a merge, before a release, or on "are the docs still right?".
argument-hint: "[<pr-number> | <commit-range> | current diff]"
---

# Doc-drift — keep docs honest against a change

## Ethos

!`sh .aif/partials/ethos-include.sh 2>/dev/null || sh ~/.claude/skills/partials/ethos-include.sh`

## Input

$ARGUMENTS

## Overview

Docs don't rot uniformly — they rot at the exact points a change touched. So work from the change outward: extract the renamed/removed/added public surfaces from the diff, then hunt the docs for every mention. This is the inverse of a docs review; it's targeted, cheap, and runs well right after a merge (see `~/.claude/aif-references/trigger-recipes.md`).

## When to use

- A PR just merged and docs may reference the old behavior
- Pre-release docs pass (pairs with `/release-notes`)
- "Update the docs for this change" / "are the docs stale?"

**Skip** for: toolkit-template drift in consumer repos (that's `/template-drift`), and writing NEW feature docs from scratch (that's authoring, not drift — though Step 3 will flag the gap).

## Process

### Step 1 — Resolve the change set

```bash
# PR number -> its diff; range -> that diff; no argument -> working diff, else HEAD~1..HEAD
gh pr diff <pr-number> 2>/dev/null || git diff <range> || git diff HEAD~1..HEAD
```

### Step 2 — Extract the public surfaces that moved

From the diff, list every **externally observable** identifier that was added, renamed, removed, or re-typed:

- API routes / RPC methods / exported functions and types
- CLI commands and flags
- Config keys, env vars, feature flags
- Error messages and exit codes users match on
- Defaults that changed value

Internal-only renames (private helpers, test scaffolding) are out of scope — say so rather than grepping the world for them.

### Step 3 — Hunt the doc surfaces

Inventory where docs live in this repo (typical: `README.md`, `docs/`, `*.md` beside code, API specs like `openapi.yaml`, per-repo `CLAUDE.md`, the workspace context file). Then, per moved surface:

```bash
grep -rn "<old-identifier>" --include="*.md" --include="*.yaml" --include="*.yml" . | grep -v node_modules | grep -v "^./.git"
```

Classify each hit:

| Class | Meaning | Action |
|---|---|---|
| **Stale** | doc contradicts the code now | fix it in this pass |
| **Missing** | new surface, no doc mentions it | add a minimal accurate entry, or flag it if it needs real authoring |
| **Historical** | changelogs, ADRs, release notes | leave — history is allowed to describe the past |

Cross-repo: when `.aif/config.yml` declares `repos:`, ask whether sibling repos' docs should be swept too (their docs often reference this repo's API); skip silently in single-repo mode.

### Step 4 — Fix, and prove what's provable

Apply the stale fixes. For doc examples that are executable (curl commands, CLI invocations, config snippets), run them where cheap and safe — a doc "fix" that shows a command that errors is worse than the drift was (ethos #5). Never invent behavior to fill a gap: if you can't verify what the new surface does, read the code until you can, or flag it (ethos #1).

### Step 5 — Ship the fix

- If invoked on the current working branch: fold the doc fixes into it (same PR as the change — docs travel with code).
- If invoked post-merge: dedicated branch + PR via the forge adapter (source `partials/forge.sh`, `aif_forge_pr_create`), body listing surface → doc-file pairs fixed and any flagged authoring gaps.

## Failure modes to avoid

1. Grepping the docs for nothing in particular — always derive targets from the diff.
2. "Fixing" docs to describe behavior you didn't verify (ethos #1).
3. Rewriting historical records (changelogs, ADRs) to match the present.
4. Silently skipping the missing-coverage class — an undocumented new flag is drift too; flag it even when authoring is out of scope.
