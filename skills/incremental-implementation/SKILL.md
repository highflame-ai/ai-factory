---
name: incremental-implementation
description: Builds multi-file changes in thin vertical slices, one repo at a time, with a working state at every step. Use when implementing any feature that touches more than one file, crosses repo boundaries, or feels too big to land in one commit. Particularly important for multi-repo features where a partial change in one repo breaks contracts the next repo expects.
---

# Incremental implementation

## Overview

Build in thin vertical slices. Implement → test → verify → commit → next slice. Each slice leaves the system in a working, testable state. On a multi-repo platform this matters more than usual: a half-finished change in a shared-contracts repo can break every consumer if the slice isn't carved correctly.

## When to use

- Any multi-file change
- Any change that crosses repo boundaries (api + web, worker + billing-service)
- Any change that adds a contract surface (new endpoint, new event type, new capability)
- Any time you're about to write more than ~100 lines without running anything

**Don't use** for single-file, single-function changes where scope is already minimal.

## Process

### Before slicing — capture the shape

Write down:

- **Goal**: one sentence
- **Repos touched**: list (check the `repos:` section of `.aif/config.yml` for the canonical names)
- **Contract surface added/changed**: any new field, endpoint, span attribute, event key
- **Verification at the end**: how do you know the whole thing works (e.g. "regression test green," "end-to-end curl returns expected JSON")

If you can't write the verification line, you don't have a clear goal yet. Stop and clarify with the user.

### Slicing strategies

**Vertical slices (preferred).** One complete path through the stack, end-to-end:

```
Slice 1: skeleton happy path — new schema column + repo method + minimal handler + dummy frontend display
Slice 2: validation + error paths
Slice 3: edge cases (concurrent writes, missing data)
Slice 4: polish (UI states, telemetry, docs)
```

Each slice ships value, exercises the full path, and is reviewable in isolation.

**Horizontal slices (fallback).** Layer-by-layer when vertical is impossible (e.g. a pure migration with no callers yet):

```
Slice 1: migration + schema
Slice 2: repo methods + tests
Slice 3: service layer
Slice 4: handler + API docs
Slice 5: frontend integration
```

Less natural; more risk that an early slice has no consumer to verify against. Use vertical when you can.

### The slice cycle

For each slice:

1. **Implement** the smallest complete piece
2. **Verify locally** — `make test`, `make lint`, `make build` per repo (or the repo's equivalents)
3. **Commit** — atomic, descriptive subject matching `org.commit_prefix_regex` (default: conventional commits; see `~/.claude/aif-references/commit-prefix-check.md`)
4. **Move on** — don't restart, don't go back to "polish" the last slice unless the next one needs it

### Cross-repo slicing rules

**Specs first.** If `/feature-prep` returned `NEW_ENTRY`, the spec-only PR against the registry at `org.spec_registry` is **slice 0**. It lands before any code. The implementation slices reference the entry ID. (Skip if `org.spec_registry` is not configured.)

**Shared contracts come before consumers.** If you're changing a schema or type in a shared-contracts repo, that PR lands first; the consumer repos' PRs follow. Reverse order = broken builds. If your config defines a `merge_order:`, follow it.

**Migrations come before code that reads new columns.** The migration is its own slice; the code that reads the new column lands after the migration is verified in the shared dev environment (describe the table via MCP if `mcp.namespace` is configured; otherwise ask the user to confirm the migration ran).

**Frontend lands after the backend is deployed.** If the web app talks to the shared environment's backend during development, frontend calls fail until the endpoint is deployed. Sequence: backend PR → deploy → verify → frontend PR.

### Verification per slice

Each slice's commit must:

- Pass the repo's tests (`make test`, `pytest`, `pnpm test`, …)
- Pass the repo's linter
- Pass the repo's build
- Leave the repo's branch in a state where the next person could check it out and run it

If a slice is "in progress" and doesn't compile, it's not a slice — split it smaller.

### Verification at the goal

When all slices are merged:

- Run the verification line you wrote at the start (regression test, e2e curl, or `/ship`'s post-deploy checks)
- If it fails: `/triage-dev` to localize, fix, repeat
- If it passes: done

## Rationalizations (and rebuttals)

| You'll be tempted to think…                                                    | Why it's wrong                                                                        |
| ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| "I'll write all the slices, then commit at the end"                            | Defeats the purpose. Each commit is a save point; bundling means no save points.       |
| "Slice 4 doesn't need a test, it's just polish"                                | Polish that breaks the happy path is a regression. Same bar.                           |
| "I'll skip the api slice's verification because the web slice needs it now"    | Frontend against a half-deployed backend = flaky local dev. Backend first, full stop.  |
| "Vertical slicing is too much overhead for this feature"                       | If the feature is small enough to skip slicing, you wouldn't have invoked this skill.  |
| "The migration slice can have the read code in it; saves a PR"                 | Then a rollback drops production reads. Migration alone, then read code alone.         |

## Red flags

- A slice's diff is > 500 lines. Too big — split.
- A slice doesn't compile / pass tests on its own. Not a slice.
- You're three slices in and haven't run anything yet. Stop, run, fix, then continue.
- The slice changes a contract but no consumer has been updated yet. Either bundle the consumer change or feature-flag the new path.
- "Slice N: cleanup" without a specific list. Cleanup is a hidden refactor; name what you're cleaning.

## Verification

Done when:

- [ ] Each slice has its own commit; no "WIP" commits left
- [ ] Each slice's repo passes its test, lint, and build commands at the time of its commit
- [ ] Goal-level verification line is green
- [ ] No slice depends on a future slice's code to compile

## Anti-patterns

- Big-bang implementation followed by one giant commit
- Slices that don't compile in isolation
- Frontend slice landing before the backend is deployed to the shared environment
- Migration slice bundled with code that reads new columns
- Cross-repo contract change landing AFTER its consumer
- "I'll fix the tests in the next PR" — tests are part of the slice
