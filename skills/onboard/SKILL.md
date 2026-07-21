---
name: onboard
description: Adopt ai-factory in an existing codebase by analyzing it and DRAFTING the fill-in surfaces — the workspace service map, starter domain experts, conventions, and .aif/config.yml — for human review, instead of leaving a wall of blank templates. Use once per repo (or workspace) when first adopting the toolkit, after /init. Turns "fill in six files by hand" into "review and correct a draft."
argument-hint: "[repo-or-workspace path] (defaults to current directory)"
---

# Onboard — draft the adoption surfaces from an existing codebase

## Ethos

!`sh .aif/partials/ethos-include.sh 2>/dev/null || sh ~/.claude/skills/partials/ethos-include.sh`

## Input

Target: $ARGUMENTS

## Overview

`/init` creates the *structure*; adoption stalls at the *content* — a new team faces blank `workspace-CLAUDE.md`, no experts, an unfilled `config.yml`. This skill reads the actual codebase and drafts those surfaces so the human edits a draft instead of authoring from scratch. **Everything it produces is a draft for review** — it never finalizes config or claims a fact it didn't read from the code (ethos #1).

## When to use

- First adoption of ai-factory in an existing repo (or a workspace of repos)
- After `/init` has scaffolded `.aif/` but the fill-in surfaces are empty
- Refreshing the drafts after a major architectural change

**Skip** for: a brand-new empty repo (nothing to analyze — fill the templates directly), and repos already onboarded (use `/expert` to add a domain, or edit the surface directly).

## Process

### Step 1 — Ensure structure, then survey the ground truth

If `.aif/` doesn't exist, run `/init` first. Then survey the repo from evidence, not assumption:

```bash
# stack + entrypoints
ls -1; git ls-files | sed 's:/.*::' | sort | uniq -c | sort -rn | head -20
cat package.json go.mod pyproject.toml Cargo.toml pom.xml 2>/dev/null | head -60
# existing docs to distill from (don't reinvent what's written)
git ls-files '*.md' 'docs/**' | head -40
# test + CI conventions
git ls-files '.github/**' 'Makefile' '*.mk' | head
```

For a workspace of repos, read `repos:` from `.aif/config.yml` (or discover siblings) and survey each. Prefer reading existing READMEs/ADRs over inferring.

### Step 2 — Detect domains

A domain is a coherent area a change tends to stay within — derived from the directory structure and dependency manifests, not guessed. Group top-level source dirs into domains (e.g. `web/` → frontend, `api/auth/` → auth, `db/`/`migrations/` → data access). For each candidate domain, note the paths it owns (these become `applies_to` globs) and the docs that describe it. Present the detected domain list to the user and confirm before drafting experts — a wrong domain map produces wrong experts.

### Step 3 — Draft each surface (all as review drafts)

Produce, in order, each clearly marked as a draft:

1. **`workspace-CLAUDE.md` service map** — one row per repo/service from the survey: language, role (from its README/entrypoints), local port if discoverable. Fill only what the code shows; leave `<placeholder>` for anything you couldn't verify, and say which rows are inferred vs sourced.
2. **`.aif/config.yml`** — populate `stack` (languages/frontends/backends/databases/ci from the manifests), `repos` (from the survey), and any `org`/`environments`/`tenancy` keys you can support from real evidence. Leave the rest as commented placeholders. NEVER invent endpoints, project ids, or secrets.
3. **Starter experts** — one `.aif/experts/<domain>.md` per confirmed domain (Step 2), via the `/expert` distillation bar: distilled from that domain's real docs+code, `applies_to` globs verified against `git ls-files`, `sources` recorded. Draft, don't dump.
4. **`.aif/context/conventions.md`** — the naming/testing/error-handling/git conventions the code actually exhibits (read a representative slice), not aspirational ones. Flag where the codebase is inconsistent rather than picking a winner silently.

### Step 4 — Present for review, finalize nothing silently

Show the user every draft with its provenance and its gaps (what you couldn't determine and why). Apply only what they confirm. Explicitly list the follow-ups the analysis couldn't fill — the auth contract, MCP namespace, deploy targets — so the blanks are visible, not forgotten.

### Step 5 — Verify the drafts hold together

- Every expert's `applies_to` matches real files (`git ls-files <glob>`).
- `.aif/config.yml` parses and its `repos:` paths exist.
- The service map names match the repos in config.
- Point the user at `/expert` (add domains), `/measure` (baseline metrics now, to measure adoption impact later), and `aif check` (wire CI).

## Failure modes to avoid

1. **Inventing facts** the code doesn't show — endpoints, project ids, an auth contract. Draft only from evidence; leave the rest as visible blanks (ethos #1).
2. **Doc-dumping into experts** instead of distilling — same bar as `/expert`.
3. **Finalizing without review** — everything here is a draft; the human owns adoption decisions.
4. **Papering over inconsistency** — if the codebase mixes two conventions, say so; don't silently canonize one.
5. **Onboarding an empty repo** — there's nothing to analyze; fill templates directly instead.
