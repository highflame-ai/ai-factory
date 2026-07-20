# Regression Markers & Profiles (fill-in template)

Template for documenting your org's end-to-end test profiles and markers, driven by the `regression:` section of `.aif/config.yml` (`regression.repo`, `regression.run_command`, `regression.profiles`). The `kind-regression-runner` agent and anyone running the suite manually load this file to pick the right profile and markers.

**To adopt:** replace the worked example below with your actual profiles and markers. If `regression:` is absent from `.aif/config.yml`, all tests are repo-local — this file doesn't apply; say so and run the repo's own test suite instead.

## Profiles (pick one)

Profiles are named subsets declared in `regression.profiles`, listed cheapest first. Worked example for a four-profile setup:

| Profile   | What it runs                                                                        | When to use                                                  |
| --------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `smoke`   | Critical paths only — web app loads, API `/healthz`, token issuance                 | After a config-only change, dependency bump, or as a CI gate |
| `control` | Smoke + control-plane flows (admin CRUD, policy sync, permission evaluation)        | Changes to control-plane services only                       |
| `ui`      | Smoke + web UI flows via Playwright                                                 | Frontend changes                                             |
| `full`    | Everything — control + data + ui                                                    | Pre-merge for risky changes; nightly                         |

Default in CI: the cheapest profile (`smoke`). Local dev iteration: `smoke` first, `full` only when smoke passes and you want full coverage.

**Profiles vs markers:** profile names live in the runner (Makefile or equivalent) and select which markers run; a profile usually composes multiple markers under the hood, so don't assume a 1:1 name mapping. Source of truth for the marker list: the regression repo's `pyproject.toml` `[tool.pytest.ini_options].markers` (or your framework's equivalent).

## Pytest markers (worked example)

Enable `--strict-markers` so a typo fails at collection. Organize markers along three axes:

**Test types:**

| Marker                     | Selects                                                  |
| -------------------------- | -------------------------------------------------------- |
| `@pytest.mark.smoke`       | Smoke profile — critical paths                           |
| `@pytest.mark.unit`        | Pure unit tests (in-process, no services)                |
| `@pytest.mark.api`         | HTTP API tests against deployed services                 |
| `@pytest.mark.integration` | Integration across 2+ services                           |
| `@pytest.mark.contract`    | Contract / interface tests between services              |
| `@pytest.mark.slow`        | > 30s; excluded from smoke                               |
| `@pytest.mark.flaky`       | Known-flaky; run with retries; tracked for stabilization |
| `@pytest.mark.destructive` | Mutates shared state in a way that requires isolation    |

**Domain (which subsystem the test exercises)** — one marker per major subsystem, e.g.:

| Marker                 | Selects                    |
| ---------------------- | --------------------------- |
| `@pytest.mark.api`     | Core API surface            |
| `@pytest.mark.billing` | Billing-service workflows   |
| `@pytest.mark.orders`  | Orders flows                |

**Cross-cutting concerns:**

| Marker                 | Selects                               |
| ---------------------- | ------------------------------------- |
| `@pytest.mark.auth`    | Authn / token issuance + verification |
| `@pytest.mark.tenancy` | Multi-tenancy isolation               |
| `@pytest.mark.rbac`    | Role-based authz                      |

**Spec gating (the promotion rule)** — only if your org keeps a spec registry (`org.spec_registry` in `.aif/config.yml`; skip this row if absent):

| Marker                            | Selects                                                                                                                    |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `@pytest.mark.capability("<ID>")` | Verifies a spec-registry entry — flips its status `planned` → `implemented`. Cross-check each ID against the registry. |

## Picking markers for a new test

Decision order — pick all that apply:

1. **Spec-gated?** If the test is the verifying test for a spec-registry entry (Step 1 of `/feature-prep` was `NEW_ENTRY`), it MUST carry the capability marker with that entry's ID. Promotion rule.
2. **Test type.** Pick exactly one of `smoke` / `unit` / `api` / `integration` / `contract` based on what the test does — smoke is for critical paths only.
3. **Domain.** Pick one or more domain markers matching which subsystem(s) the test exercises.
4. **Cross-cutting.** If the test asserts on `auth` / `tenancy` / `rbac`, add the marker — drives per-concern coverage reporting.
5. **Slow / flaky / destructive.** Add as needed.

A test can carry multiple markers. `@pytest.mark.smoke @pytest.mark.tenancy @pytest.mark.capability("<ID>")` is normal.

## Lifecycle commands (worked example)

From the regression repo (`regression.repo`), using `regression.run_command` as the base — a Makefile-driven local-cluster setup might look like:

```bash
# Bring up the local cluster, deploy services, run tests, tear down
make test PROFILE=smoke

# Faster iteration (re-uses an existing cluster)
make test-quick PROFILE=smoke

# Even faster — re-runs pytest only against the existing deployed stack
make test-only PROFILE=smoke MARKERS="-k <test_name>"
```

Document where reports land (e.g. `reports/runs/<id>/` — JSON results, JUnit XML, captured logs from each service pod).

## When to use which command

| Situation                            | Command                                                               |
| ------------------------------------ | ---------------------------------------------------------------------- |
| First run of the day / after pulling | `make test PROFILE=smoke` (full lifecycle, clean)                     |
| Iterating on one test                | `make test-only MARKERS="-k <test_name>"`                             |
| After changing service code          | `make test-quick PROFILE=smoke` (rebuilds + redeploys, keeps cluster) |
| Investigating a flake                | `make test-only` repeatedly + watch logs                              |

## Reading reports

Document your report layout so agents can parse failures, e.g. `reports/runs/<id>/`:

- `pytest-results.json` — top-level pass/fail per test
- `junit.xml` — for CI ingestion
- `pod-logs/<pod>.log` — one file per service pod from the run
- `events.json` — cluster events (image pulls, OOM, etc.)

The `kind-regression-runner` agent parses these on failure; if invoking manually, start with the results JSON and follow into the failing test's pod log.

## Don't do this

- Don't tag fine-grained correctness tests with `@pytest.mark.smoke` to "force coverage." Smoke is a P0 gate; bloat dilutes signal.
- Don't add a capability marker for an ID that doesn't exist in the spec registry. Cross-referencing dashboards flag orphan markers.
- Don't introduce a new marker without registering it — `--strict-markers` rejects unknown markers at collection time.
- Don't run `full` on every iteration. `smoke` first; `full` once smoke is green.
