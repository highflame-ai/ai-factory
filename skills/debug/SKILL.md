---
name: debug
description: Systematic root-cause debugging for local repros, failing tests, and broken builds. Phase 1 = build a fast deterministic feedback loop (this is the skill); the rest is mechanical. Use when tests fail, builds break, or local behavior doesn't match expectations. For shared-environment issues use /triage-dev instead.
---

# Debug — local repro and root-cause

## Overview

When a test fails or a local repro misbehaves, **stop adding features** and follow the discipline. Guessing wastes time. This skill is for **local repro** — failing unit tests, broken builds, integration tests against the local stack. For issues in your org's shared dev environment use `/triage-dev`.

The whole skill turns on one idea: **if you have a fast, deterministic, agent-runnable pass/fail signal for the bug, you will find the cause. If you don't, no amount of staring at code will save you.** Phase 1 below is where the disproportionate effort goes; everything after consumes the signal Phase 1 produces.

## When to use

- A test fails after a code change
- A build breaks
- Local behavior doesn't match expectations (unit, integration, repo-local e2e)
- "It worked yesterday, what did I break?"

**Don't use** for:

- "Something's wrong in the shared dev environment" → `/triage-dev`
- "The org-level regression suite failed" → the kind-regression-runner agent (when `regression:` is configured in `.aif/config.yml`; it knows the report layout)
- "CI is red" → `@pr-shepherd` for mechanical failures; `/triage-dev` if a deploy step failed

## The stop-the-line rule

```
1. STOP adding features
2. PRESERVE evidence (error output, logs, repro steps)
3. Build the feedback loop (Phase 1)
4. Use it to localize and root-cause (Phases 2–3)
5. FIX the root cause (Phase 4)
6. GUARD against recurrence (Phase 5)
7. RESUME only after verification passes (Phase 6)
```

Don't push past a failing test. Errors compound.

---

## Phase 1 — Build a feedback loop

**This is the skill.** Spend disproportionate effort here. Everything else is mechanical once you have a 2-second deterministic pass/fail.

### Ways to construct one — try in roughly this order

1. **Failing test** at whatever seam reaches the bug — unit, integration, e2e.
   - Go: `go test ./internal/<pkg>/... -run TestSpecific -v -count=1`
   - Python: `pytest tests/path/test_specific.py::test_specific -vv`
   - JS/TS: `pnpm --filter <package> test -- --grep "test name"`
2. **Curl / HTTP script** against a running local service.
   - `curl -sv -H "Authorization: Bearer $TOKEN" http://localhost:<port>/v1/...`
   - If your services use JWTs, see `~/.claude/aif-references/jwt-checklist.md` for token issuance
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser script** (Playwright) — drives the web UI, asserts on DOM / console / network.
5. **Replay a captured trace.** Save the offending request/payload to disk; feed it to the code path in isolation. Capture the actual request body from your tracing tool and replay it locally.
6. **Throwaway harness.** Spin up the minimum subset (just the API + DB, or just the failing service + a stub of its dependency) that exercises the bug with one function call. Beats booting the full local stack (`local_stack.up_command`).
7. **Property / fuzz loop.** If the bug is "sometimes wrong output", run 1000 random inputs.
8. **Bisection harness.** If the bug appeared between two known states (commit, dataset), automate `git bisect run`.
9. **Differential loop.** Same input through old-version vs new-version (or two configs); diff outputs. Useful when migrating schema versions or config formats.
10. **HITL bash script.** Last resort — drive a human through structured prompts and capture their answer. Better than ad-hoc back-and-forth.

**Build the right feedback loop, and the bug is 90% fixed.**

### Iterate on the loop itself

Treat the loop as a product. Once you have *a* loop, ask:

- **Faster?** Cache setup, skip unrelated init, narrow the test scope, avoid booting the full stack if a unit harness will do.
- **Sharper signal?** Assert on the specific symptom (the wrong tenant ID in the response), not "didn't crash".
- **More deterministic?** Pin time (`clockwork` / `freezegun`), seed RNG, isolate filesystem to `t.TempDir()`, freeze network, use `testcontainers` for ephemeral DB.

A 30-second flaky loop is barely better than no loop. A 2-second deterministic loop is a debugging superpower.

### Non-deterministic bugs

Goal is not a clean repro but a **higher reproduction rate**. Loop the trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable; 1% is not — keep raising the rate.

For cross-service races specifically (write-then-read-back through an async pipeline, span emission vs. read-back): amplify with repeated runs — e.g. `pytest -p no:cacheprovider --count 50` — or delegate to the kind-regression-runner agent if `regression:` is configured.

### When you genuinely cannot build a loop

Stop and say so explicitly. List what you tried. Ask the user for: (a) access to whatever environment reproduces it (often the shared dev environment via `/triage-dev`), (b) a captured artifact (HAR file, trace export, log dump), or (c) permission to add temporary instrumentation. **Do not proceed to hypothesise without a loop.**

---

## Phase 2 — Localize using the loop

Where does the failure happen? Be specific — "in the handler" is not enough; you want **file:line**. The loop you built lets you bisect by editing/reverting:

- **Failing assertion** → read the assertion. What value did it see vs expect? Print both.
- **Panic / stack trace** → bottom of trace is the proximate cause; top is the entry point.
- **Wrong output, no error** → bisect via prints at suspected branches (`fmt.Printf`, `console.log`, `print`). Keep the loop running between each print add.
- **Behavior depends on data** → query the DB / cache to confirm input. Locally: `psql` or `redis-cli`. In the shared environment: MCP DB tools (`mcp__<namespace>__*`, if `mcp.namespace` is configured; otherwise ask the user for a query result rather than guessing).
- **Race / timing** → add `time.Now().UnixNano()` logs around the section; run the loop 100× in parallel.

Don't skip this. "I'll just fix what I think is wrong" is how you fix three symptoms and miss the root cause.

---

## Phase 3 — Root cause vs symptom (the three Whys)

A change that makes the test pass is not necessarily a fix. Ask:

1. **Why does this fail?** (the proximate cause — what assertion, what nil, what mismatch)
2. **Why does the proximate cause exist?** (the underlying bug — wrong contract, missing case, race, stale state)
3. **Why didn't existing tests catch it?** (gap in coverage — the guard for Phase 5)

A real fix answers all three. A surface fix answers only the first.

---

## Phase 4 — Fix

Implement the smallest change that addresses the root cause. Resist:

- "While I'm here, let me clean up X" — out of scope; split if it's real.
- "Defensive `if x == nil`" — only if `nil` is genuinely possible per the contract.
- "Catch and ignore" — never; if you can't handle it, propagate.

Re-run the loop. It should flip red → green from the fix alone, no other changes.

---

## Phase 5 — Guard against recurrence

For every bug fix, add or update a test that would have caught it. The test:

- **Fails before the fix** (verify by reverting the fix locally — if it still passes, the test doesn't exercise the bug)
- **Passes with the fix**
- **Lives in the right place** per `/feature-prep` Step 2 (usually `REPO_LOCAL`; `REGRESSION` only if cross-service or user-facing, and only when `regression:` is configured)

If the bug involved any of your tenancy keys (`tenancy.keys` in `.aif/config.yml`), the test must include the multi-tenancy assertion (a query that should NOT return another tenant's data). See `~/.claude/aif-references/multi-tenancy-checklist.md`.

The test you add IS the loop you built in Phase 1, promoted to permanent. If your Phase 1 loop was a curl script, write an integration test that does the same call. If it was a component test, that test was already most of the way there.

---

## Phase 6 — Verify

Run the failing scenario AND the broader suite:

```bash
# Repo-level
make test
make lint
make build
```

For touches that cross services: run the org regression suite via the kind-regression-runner agent (`regression.run_command`; skip and say so if `regression:` is not configured).
For UI bugs: actually open the page in a browser, exercise the path, confirm the original symptom is gone.

---

## Special case — a flaky test

"It fails sometimes" is a root-causable bug, never a `skip`/quarantine candidate (ethos #6 — a quarantined test is a contract you stopped enforcing). The phases above apply with one twist: the feedback loop must first make the flake *reproducible on demand*.

1. **Classify** — rerun the single test 20–50× in isolation (`pytest --count`, `go test -count=50 -run <name>`, or a shell loop). Fails deterministically → it's a normal bug, go to Phase 2. Fails intermittently in isolation → intrinsic flake. Passes in isolation but fails in the suite → ordering/shared-state flake.
2. **Bisect the flake source** by making one variable at a time deterministic and re-measuring the failure rate: fixed seed (randomness), fake clock (timing), serial execution (parallelism), fresh fixture per run (shared state), stubbed network (external dependency), same-order run with `--seed`/`-p no:randomly`-style flags (ordering). The variable whose pinning drops the failure rate to zero IS the localization — proceed to Phase 3 on it.
3. **Fix the cause, not the symptom**: a sleep made longer is a symptom fix (the race is still there); an await/synchronization point, an isolated fixture, or an injected clock is a cause fix.
4. **Guard**: after fixing, rerun the original 20–50× loop — the failure rate must be exactly zero, and the loop command goes in the PR body as evidence.

If the fix is genuinely out of scope right now, file an issue with the classification evidence and leave the test RUNNING — a red-sometimes test that's tracked beats a green suite that's lying.

## Common gotchas

- **Multi-tenancy bug** → almost always a missing tenancy-key filter (see `tenancy.keys`). Read `~/.claude/aif-references/multi-tenancy-checklist.md`.
- **JWT validation failure** → algorithm pinning, key file path, clock skew. Read `~/.claude/aif-references/jwt-checklist.md`.
- **Migration didn't run / column missing** → check the ORM tag matches the column name; check the migration is registered where your framework discovers it.
- **Soft-deleted row leaks through a read** → missing "is active" filter.
- **Frontend shows stale data** → the query-cache key is missing a tenancy key, so one tenant's cache serves another's view.
- **Deployed service behaves differently from local** → test against the deployed version too (via MCP tools or the environment's endpoints); local and shared configs diverge.
- **Span doesn't appear in your tracing tool** → check the collector endpoint is reachable; check span attributes match your org's telemetry schema.
- **"Works locally, fails in CI"** → environmental difference. Common culprits: missing env var, absent credential file, port collisions. Don't skip-mark it.
- **Flaky cross-service test** → check if it depends on an eventually-consistent read path; add a poll loop with bounded retries, not a `sleep`.

## Rationalizations (and rebuttals)

| You'll be tempted to think…                  | Why it's wrong                                                                                                |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| "I'll skip Phase 1; I know what's wrong"     | Half the time you're wrong. A loop is a forcing function that proves it.                                      |
| "The loop is too hard to build, I'll guess"  | The loop is the skill. If building it is hard, the bug is hard — guessing makes it harder.                    |
| "The fix is obvious; skip the test"          | The bug existed because no test caught it. Adding the guard IS part of the fix.                               |
| "Wrap it in try/catch and move on"           | You've hidden the bug, not fixed it. Catch is for known cases with known handling.                            |
| "It only fails in CI; works locally"         | Real bug — environmental difference. Don't skip-mark it.                                                      |
| "It's flaky; I'll rerun"                     | Flakiness is a signal of a race or unbounded resource. Treat as a bug; raise the repro rate per Phase 1.      |
| "Reproducing it 1×/100 is good enough"       | No, that's debugging by ESP. Push the rate up before hypothesising.                                           |

## Red flags

- You're three "fixes" in and the test still fails. You're addressing symptoms; back up to Phase 2.
- You found the proximate cause and didn't ask the second and third Whys. The deeper bug is still there.
- You skipped Phase 5. The same bug will reappear; guarantee it.
- Your fix touches files unrelated to the failure. Out of scope; revert and split.
- The test you added passes both with AND without the fix. The test doesn't actually exercise the bug.
- You didn't build a loop. You're hypothesising without a signal. STOP and build the loop.

## Verification

Done when:

- [ ] A fast, deterministic, agent-runnable pass/fail loop exists (Phase 1)
- [ ] Loop flips red → green from the fix ALONE
- [ ] Root cause named at file:line, with all three Whys answered
- [ ] Fix is minimal and targets the root cause
- [ ] New / updated test reproduces the loop, fails before the fix, passes after
- [ ] Full repo test suite passes
- [ ] If multi-service: regression smoke profile passes (via the kind-regression-runner agent, when `regression:` is configured)

## Anti-patterns

- Hypothesising without a feedback loop
- Fixing symptoms without finding the root cause
- "Defensive" code that hides the bug
- Skipping the regression test
- Marking flaky tests as skip
- Bundling refactors with the bug fix
- Pushing through a failing test to work on the next feature
- Using `sleep` to paper over a race instead of a bounded poll
