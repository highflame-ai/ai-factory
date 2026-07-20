---
name: git-workflow
description: Git conventions — commit-subject prefixes that pass your CI's commit check (configured via `org.commit_prefix_regex`, defaulting to Conventional Commits), atomic commits, branch naming, when to worktree vs branch, and how to drive a PR through CI. Use when committing, branching, or about to open a PR. Pairs with the local `commit-prefix-check.sh` hook (which enforces) and the `pr-shepherd` agent (which auto-fixes mechanical CI failures).
---

# Git workflow — commit, branch, PR conventions

## Overview

Most orgs gate commit subjects in CI with an anchored regex. Locally, the `commit-prefix-check.sh` hook enforces the same gate on `git commit -m`, so the mistake is caught in seconds instead of bouncing off CI minutes later. This skill encodes the rules, the rationalizations that lead to broken commits, and the surrounding workflow (branching, worktrees, PR opens).

## When to use

- About to commit (especially if your org's convention differs from plain Conventional Commits)
- Branching for a new feature
- Opening a PR
- Untangling a "the hook keeps blocking me" loop

## The commit-prefix regex

The `commit-prefix-check.sh` hook resolves the allowed regex in this order:

1. `AIF_COMMIT_PREFIX_REGEX` env var (highest precedence)
2. `.aif/config.yml` → `org.commit_prefix_regex`
3. Default: **Conventional Commits** — `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`, each with an optional scope (`feat(api):`) and optional `!` for breaking changes, plus the machine-generated subjects `Merge`, `Revert`, `Bump`, `build(deps)`.

Under the default, scoped forms like `feat(api):` and `fix(billing-service):` are **allowed**. If your CI enforces something stricter or different, set `org.commit_prefix_regex` to mirror it exactly — the hook and CI must agree or the hook is theater.

For the full regex, common rewrites, and the rationale, **read `~/.claude/aif-references/commit-prefix-check.md`**. Don't restate the table here — the reference is the source of truth.

## Atomic commits

Each commit does one logical thing. If you can describe two unrelated things in the subject, it's two commits.

```
# Good
feat: add billing admin module
feat: add billing CRUD endpoints
fix: handle nil rule text in policy validator

# Bad
feat: add billing module + fix unrelated bug + refactor base/
```

Atomic means:

- Reverts cleanly (one commit = one decision)
- Reads cleanly in `git log`
- Reviews cleanly per-commit if the reviewer asks

## Branch naming

| Pattern                     | Use for                                                             |
| --------------------------- | ------------------------------------------------------------------- |
| `feat/<short-description>`  | New features                                                        |
| `fix/<short-description>`   | Bug fixes                                                           |
| `chore/<short-description>` | CI, hooks, settings, tooling, configs                               |
| `chore/spec-<id>`           | Spec-registry-only PRs (per `/feature-prep`; needs `org.spec_registry`) |
| `revert/<sha-or-pr>`        | Reverts                                                             |

If your org's branch conventions differ, follow the org's — these are the defaults, not a gate.

Keep branches short-lived (1–3 days). Long-lived branches accumulate merge risk; prefer feature flags for incomplete work.

## Worktree vs branch

| Use                                                     | Worktree | Just a branch |
| ------------------------------------------------------- | -------- | ------------- |
| Working on multiple changes in parallel                 | ✓        |               |
| Spec-only PR while you have unrelated WIP               | ✓        |               |
| Anything off `origin/main` while local main has commits | ✓        |               |
| Single linear stream of work                            |          | ✓             |

Worktree pattern:

```bash
cd <repo-root>                 # e.g. the repo hosting org.spec_registry
git fetch origin main
git worktree add /tmp/spec-worktree -b chore/spec-<id> origin/main
cd /tmp/spec-worktree
# work, commit, push
git worktree remove /tmp/spec-worktree   # when done
```

## The commit cycle

1. **Stage with intent** — `git add <specific-files>`, not `git add -A`. Avoids accidentally committing `.env`, scratch files, or someone else's work.
2. **Subject line first** — write it before the body. If you can't, you don't know what the commit is.
3. **`git commit`** — the local hook validates the prefix. If it blocks, fix the subject (don't `--no-verify`).
4. **`git push -u origin <branch>`** — first push sets up tracking.

If `commit-prefix-check.sh` blocks: fix the subject. If the hook's regex genuinely doesn't match your CI's, fix `org.commit_prefix_regex` in `.aif/config.yml`. Don't override unless you have a specific one-off reason (`CLAUDE_DISABLE_COMMIT_PREFIX_CHECK=1`).

If `precommit-gate.sh` blocks: fix the lint/format/type errors it surfaced. Don't `--no-verify`. The hook is the same checks CI runs; bypassing locally just defers the failure.

## Opening a PR

```bash
. .aif/partials/forge.sh 2>/dev/null || . ~/.claude/skills/partials/forge.sh
aif_forge_pr_create --title "<subject-style title under 70 chars>" --body "$(cat <<'EOF'
## Summary
- <bullet 1>
- <bullet 2>

## Test plan
- [ ] <how the user verifies>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

After push, delegate to `pr-shepherd` agent for mechanical CI failures (CVE bumps, formatter drift, lockfile drift). For automated bot review, delegate to `gemini-reviewer`.

For the full pre-merge orchestration, use `/ship`.

## Multi-PR features

When `/feature-prep` returned `NEW_ENTRY` and `org.spec_registry` is configured, the sequence is three PRs:

1. **Spec PR** against the repo hosting `org.spec_registry` — the registry file only. Branch: `chore/spec-<id>`. `feat:` subject.
2. **Implementation PR(s)** in the touched services. Reference the entry ID. Repo-local tests here.
3. **Regression PR** — cross-repo: `regression.repo` + the spec registry (flips `planned` → `implemented`). The one allowed cross-repo PR pattern.

If `org.spec_registry` is not configured, there is no spec PR — go straight to implementation PR(s), and put end-to-end tests wherever `regression:` points (or repo-local if that's unset too).

## Rationalizations (and rebuttals)

| You'll be tempted to think…                          | Why it's wrong                                                                                                       |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| "The hook's regex is wrong, my subject is fine"      | Then fix `org.commit_prefix_regex` to mirror CI — don't bypass. If the hook and CI disagree, the config is the bug.  |
| "I'll bypass the hook this once with `--no-verify`"  | The hook is the same check as CI. Bypassing means CI rejects in 5 minutes anyway, after you've waited for the build. |
| "I'll squash everything into one commit at merge"    | Then revert is all-or-nothing. Atomic commits give you fine-grained revert.                                          |
| "I'll branch off my current work-in-progress branch" | Then your PR carries unrelated diffs. Branch off `origin/main` (or use a worktree).                                  |
| "Long-lived branch is fine, it's just my own work"   | Every day off `main` is merge-risk debt. Short branches; feature flags for incomplete work.                          |
| "git add -A is faster"                               | Until you commit `.env` or someone else's untracked file. Stage specific files.                                      |

## Red flags

- You're using `--no-verify`. Diagnose what the hook is blocking; fix that.
- Your branch has been alive for > 3 days with no merge target in sight. Either merge it or rebase / split.
- You staged with `git add -A` and the diff includes files you don't recognize. Unstage and look.
- You amended a commit that's already pushed. Force-pushing can lose work; prefer a new commit.
- The PR title is generic ("Update files"). Subject should describe the change.

## Verification

Done when:

- [ ] Commit subjects all match the resolved regex (the hook would have caught any that didn't)
- [ ] No `--no-verify` in any commit
- [ ] Branch is off a recent `origin/main`
- [ ] PR body has Summary + Test plan
- [ ] CI is green; if not, `pr-shepherd` is delegated for mechanical fixes

## Anti-patterns

- Commit subjects that dodge the convention (whatever `org.commit_prefix_regex` resolves to)
- `git commit --no-verify` to bypass hooks
- `git add -A` for partial commits
- Force-pushing to shared branches
- Branching off feature branches (chains break on merge)
- Squashing atomic commits at merge time
- Long-lived feature branches in lieu of feature flags
