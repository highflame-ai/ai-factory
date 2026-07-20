---
name: release-notes
description: Draft multi-audience release notes (customer, engineering, executive) from a git tag or range — classifies commits and merged PRs by type, pulls context from linked specs, and produces a reviewable draft. Never publishes anything itself. Use when cutting a release, tagging a version, or when asked "what shipped since <tag>?".
argument-hint: "<tag | range | 'since last tag'> [--audience customer|engineering|executive|all]"
---

# Release notes — multi-audience draft from a git range

## Ethos

!`sh .aif/partials/ethos-include.sh 2>/dev/null || sh ~/.claude/skills/partials/ethos-include.sh`

## Input

$ARGUMENTS

## Overview

Turns "what shipped?" from an archaeology exercise into a draft: resolve the range, gather the commits and merged PRs, classify them, and write notes tuned per audience. The output is a **draft artifact for human review** — this skill never tags, never publishes, never posts.

## When to use

- Cutting a release / about to tag
- "Write the release notes for v1.4" / "what shipped since v1.3?"
- A recurring release digest (see `~/.claude/aif-references/trigger-recipes.md` for scheduling)

**Skip** for: single-PR summaries (the PR description already is one), and changelogs for unreleased work (use `/status`).

## Process

### Step 1 — Resolve the range

```sh
# Explicit tag/range wins. Default: last tag -> HEAD.
last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
[ -n "$last_tag" ] && echo "range: ${last_tag}..HEAD" || echo "no tags found"
```

If there are no tags and no explicit range was given, STOP and ask the user for a starting point — guessing a range produces notes that misrepresent the release.

### Step 2 — Gather what shipped

```bash
git log --no-merges --pretty='%h %s' <range>
git log --merges --pretty='%h %s' <range>          # merged PRs (merge-commit repos)
```

For PR titles/bodies and linked issues, use `gh pr list --state merged --search "merged:>**<date>**"` or read the merge commits. Cross-repo releases: if `.aif/config.yml` declares `repos:`, ask whether siblings are part of this release and repeat per repo (skip silently in single-repo mode).

### Step 3 — Classify

Bucket each change using the commit-prefix convention (`org.commit_prefix_regex`; default Conventional Commits):

| Bucket | From | Audience weight |
|---|---|---|
| Breaking changes | `!` suffix, `BREAKING CHANGE:` footers, major API removals | all audiences, first |
| Features | `feat:` | customer + engineering |
| Fixes | `fix:` | customer (user-visible only) + engineering |
| Performance / reliability | `perf:`, infra `fix:` | engineering; customer only if user-visible |
| Internal (refactor/test/build/chore/docs) | everything else | engineering only, one compressed line |

Read the diff (not just the subject) for anything ambiguous — a `fix:` that changes a public contract is a breaking change no matter what the subject says (ethos #1). If `.aif/specs/` or `org.spec_registry` entries are referenced by the changes, pull the requirement titles for accurate feature descriptions; skip when neither exists.

### Step 4 — Draft per audience

Write to `${TMPDIR:-/tmp}/release-notes-<version>.md` (resolve the path in shell first — the Write tool doesn't expand variables). One file, three sections (or only the requested `--audience`):

```markdown
# <version> — <date>

## Customer notes
<user-visible value only. No internal ticket ids, no repo names. Breaking changes
lead with WHAT the user must do. Empty buckets are omitted, never padded.>

## Engineering notes
<every change grouped by bucket, with PR links and migration steps. Breaking
changes include the upgrade path.>

## Executive summary
<3-5 sentences: what shipped, why it matters, risk posture. No bullet lists.>
```

### Step 5 — Verify, then hand off

- Every breaking change in the draft traces to a real commit/PR (cite it).
- Nothing in the customer section references internal-only surfaces.
- Present the draft path to the user. Publishing (GitHub release, docs site, email) is the human's call — offer, don't act.

## Failure modes to avoid

1. Trusting commit subjects over diffs — subjects lie; the release notes must not (ethos #1).
2. Padding empty sections ("various bug fixes and improvements") — omit instead.
3. Publishing anywhere without explicit human approval.
4. Treating the newest tag as the release being cut — the range END is usually HEAD or a release branch; confirm.
