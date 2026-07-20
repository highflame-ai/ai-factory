---
name: dep-update
description: Safe dependency update loop — inventory outdated/vulnerable dependencies across the repo's toolchains, vet each candidate's changelog for breaking risk, update in an isolated branch, prove it with tests (and the org regression smoke when configured), and open one reviewable PR per coherent batch. Use for "update dependencies", "is anything vulnerable?", CVE bumps, or a scheduled hygiene pass.
argument-hint: "[<package> | scan] [--security-only]"
---

# Dep-update — vetted dependency updates with a regression loop

## Ethos

!`sh .aif/partials/ethos-include.sh 2>/dev/null || sh ~/.claude/skills/partials/ethos-include.sh`

## Input

$ARGUMENTS

## Overview

Dependency updates fail in two ways: nobody does them (drift + CVEs pile up), or someone bulk-updates everything and ships an untested behavior change. This skill does neither — it selects a small, coherent batch, reads what actually changed upstream, and proves the update against the repo's own tests before a PR exists.

## When to use

- "Update dependencies" / "bump <package>" / "anything vulnerable?"
- A dependency-scan finding (Dependabot, `npm audit`, scanner CVE) needs a vetted fix
- Scheduled hygiene (see `~/.claude/aif-references/trigger-recipes.md`)

**Skip** for: lockfile-only drift repair after a merge (that's `@pr-shepherd`'s mechanical fix), and major framework migrations (that's a feature — `/spec` it).

## Process

### Step 1 — Inventory by toolchain

Detect manifests and use each toolchain's own outdated/audit surface; skip toolchains not present and say so:

```bash
[ -f go.mod ]        && go list -u -m all 2>/dev/null | grep '\[' | head -30
[ -f package.json ]  && { (command -v pnpm >/dev/null && pnpm outdated) || npm outdated; npm audit --omit=dev 2>/dev/null | tail -20; }
[ -f requirements.txt ] || [ -f pyproject.toml ] && python3 -m pip list --outdated 2>/dev/null | head -30
[ -f Cargo.toml ]    && (command -v cargo-audit >/dev/null && cargo audit 2>/dev/null | tail -20 || echo "cargo-audit not installed — skipping vuln scan")
```

### Step 2 — Prioritize and batch

1. **Security advisories** first — always their own batch, smallest possible diff.
2. **Patch/minor updates** of the same ecosystem may batch together.
3. **Major versions** — one per batch, never mixed with anything else, and only with the user's explicit go-ahead (`--security-only` excludes them entirely).

Cap a batch at what one reviewer can actually review. If the inventory is huge, propose an order and do the top batch; don't try to drain the backlog in one PR.

### Step 3 — Vet each candidate

Before touching a manifest, read the dependency's changelog/release notes between the current and target versions (`gh release view`, the repo's CHANGELOG, or the registry page). You are looking for: breaking changes, behavior changes in defaults, dropped platform support, and transitive requirement bumps. Semver is a claim, not a proof (ethos #7) — a minor bump with a scary changelog gets demoted to its own batch or skipped with a note.

### Step 4 — Update on an isolated branch

```bash
git checkout -b chore/dep-update-<batch-slug> origin/<default-branch>
# apply the update with the toolchain's own tool (go get -u <mod>@<ver>,
# pnpm up <pkg>@<ver>, etc.) — never hand-edit lockfiles
```

### Step 5 — Prove it

- Build + full repo test suite + linters (the same commands CI runs; `stack:` in `.aif/config.yml` and the Makefile are the sources of truth).
- If `regression:` is configured in `.aif/config.yml`, run the cheapest profile via the kind-regression-runner agent; skip and say so when unconfigured.
- If anything fails: investigate whether the failure is the dependency's breaking change (document it, drop the candidate to its own batch or skip) — never pin-and-ignore or weaken the test (ethos #6).

### Step 6 — One PR per batch

```sh
. .aif/partials/forge.sh 2>/dev/null || . ~/.claude/skills/partials/forge.sh
aif_forge_pr_create --title "<prefix per org.commit_prefix_regex>: update <batch summary>" --body "<per-dep: old -> new, changelog risk notes, test evidence>"
```

The body must carry, per dependency: version delta, the changelog-derived risk note, and the test evidence. Hand the PR to `@pr-shepherd` if CI babysitting is expected.

## Failure modes to avoid

1. Bulk-updating everything at once — unreviewable and unbisectable.
2. Trusting semver instead of reading the changelog (ethos #1, #7).
3. "Tests fail, so pin the old transitive version and move on" — that's borrowing at high interest (ethos #6); surface it instead.
4. Updating lockfiles by hand.
5. Mixing a security fix into a large routine batch — the security fix must be able to merge alone.
