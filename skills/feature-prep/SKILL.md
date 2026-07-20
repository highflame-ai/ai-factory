---
name: feature-prep
description: At the start of any non-trivial feature, identify (1) whether it introduces or changes a platform capability/invariant that needs an entry in your org's spec registry (`org.spec_registry`) FIRST, and (2) where its tests belong (org regression suite vs repo-local). Invoke proactively before writing implementation code so the spec stays a leading indicator and the regression suite stays small + high-signal. Triggers: "I'm starting work on X", "we need to add Y", any non-trivial multi-file feature request that crosses a service boundary or surfaces in a user-facing app/SDK/public API.
---

# Feature prep — spec registry + test placement

## Overview

Run this skill **before writing implementation code** for any non-trivial feature. It produces two answers:

1. **Does your org's spec registry need an update first?** → If yes, open a tiny PR against the registry file (path from `org.spec_registry` in `.aif/config.yml`, e.g. `../architecture/capabilities.yaml`) before anything else.
2. **Where do the tests belong?** → Org regression suite (path from `regression.repo`) only if specific criteria are met; repo-local otherwise.

The common path is `NO_UPDATE` + `REPO_LOCAL`. Most features add behavior to one service and ship; this skill exists to flag the rarer cases that need spec entries or regression coverage, not to manufacture work.

### Step 0 — config check

Read `.aif/config.yml` first. Both halves of this skill are driven by optional config:

- No `org.spec_registry` → there is no registry gate. Step 1 is always `NO_UPDATE`.
- No `regression.repo` → there is no org regression suite. Every test is repo-local.

If NEITHER key is configured, the whole answer is one line — say it and stop; don't ceremonialize:

```
feature-prep: no spec registry, no org regression suite configured — NO_UPDATE, tests repo-local. proceed.
```

## When to use

- Starting any non-trivial feature that crosses a service boundary
- Adding a new user-visible behavior in a user-facing app / SDK / public API
- Touching a cross-service contract (e.g. worker → analytics event shape, api → auth claims)
- Removing or deprecating a capability the platform used to promise

**Skip** for: pure bug fixes that restore existing-spec behavior, internal refactors with no contract change, dev-tooling changes (hooks, settings, this folder).

## Process

### Step 1 — spec registry check

(Only when `org.spec_registry` is configured — otherwise outcome is `NO_UPDATE`, move to Step 2.)

A well-shaped registry distinguishes two entry kinds:

| Kind         | Verifies                                       |
| ------------ | ---------------------------------------------- |
| `capability` | Positive claim — "the platform does X"         |
| `invariant`  | Negative claim — "the platform never allows X" |

Same shape (id, area/primitive, title, description, doc, status, owner). Typical status lifecycle: `planned` → `implemented` (only flipped when the verifying test lands). **Follow your registry's own conventions** — read its header comments or companion doc before drafting anything.

**Update the spec when ANY of these is true:**

- New platform-level guarantee (capability) or prohibition (invariant) — discoverable by reading the spec
- Wording or contract change to an existing entry — edit the entry, never renumber
- New user-visible or integrator-visible behavior surfaced through a user-facing app, SDK, or public API
- Cross-service contract change other services depend on

**Special case — retirement.** Removing a capability the platform used to promise = `EDIT_EXISTING` with `status: retired` and a one-line `retired_reason`. Never delete the entry; IDs are permanent. Replace-style features list TWO outcomes: `EDIT_EXISTING` (retire) AND `NEW_ENTRY` (the replacement) — both can land in the same spec-only PR.

**Pick the area/primitive.** Most registries organize entries under a small taxonomy of platform primitives or domains (identity, authorization, tenancy, observability, …). Read the taxonomy from the registry itself — never invent one from memory. If the feature genuinely doesn't fit any existing area, that's `NEW_PRIMITIVE` — STOP and surface to the user; a new platform axis is not something to draft autonomously.

**Pick the next ID.** Follow the registry's ID format (a common shape is `<KIND>-<AREA>-<NNN>` with NNN monotonic per bucket):

```bash
grep -E "^[[:space:]]*- id: " <org.spec_registry path> | sort -V | tail -5
```

Increment the highest in the bucket. Never reuse retired IDs.

**Workflow when an update is needed.** Worktree off `origin/main` of the repo containing the registry, branch `chore/spec-<id>`, edit the registry file ONLY, commit subject matching `org.commit_prefix_regex` (see `~/.claude/aif-references/commit-prefix-check.md`), tiny spec-only PR, get it merged, THEN start implementation referencing the entry ID. The `planned` → `implemented` promotion lands later in the PR that adds the verifying test.

### Step 2 — where do the tests go?

The org regression suite (`regression.repo`) is a **small, high-signal** suite. Fine-grained correctness there dilutes signal and trains people to ignore failures. The rule keeps it small.

If `regression.repo` is NOT configured, every `REGRESSION` outcome below degrades to `REPO_LOCAL`: put the end-to-end test in the repo that owns the flow, and say so explicitly in your output.

**Step 2 short-circuit.** If Step 1 = `NEW_ENTRY`, **at least one regression test is required**, tagged with the entry ID using your suite's marker convention (e.g. `@pytest.mark.capability("<ID>")`). Skip Step 2a; go straight to Step 2b's REGRESSION outcome. This test flips `planned` → `implemented` (the promotion rule). Multiple facets → multiple tests under the same marker.

The hard rule covers `NEW_ENTRY` only. `EDIT_EXISTING`, `NO_UPDATE`, and `NEW_PRIMITIVE` use Step 2a as normal.

**Repo-local tests can — and often should — live alongside.** A `NEW_ENTRY` feature usually wants both: REGRESSION (mandatory, flips status) + REPO_LOCAL (fast-feedback unit/integration in the originating repo).

#### Step 2a — does this need a NEW test at all?

Often no. Skip Step 2b if:

- **Pure refactor with existing coverage** — same external behavior; existing tests cover the contract
- **Trivial change** — doc edit, comment, single-line fix
- **Existing test extends naturally** → use `EXTEND_EXISTING` and point at the test
- **Configuration/tooling change** — CI itself is the test
- **Spec-only PR** — verifying test arrives in the implementation PR

#### Step 2b — decision tree (when a new test IS needed)

Three questions in order:

1. **End-to-end flow?** (real services, real network, real data path)
   - **No** → `REPO_LOCAL` (unit or integration). Stop.
   - **Yes** → continue.

2. **2+ services?** (e.g. api + worker + database pipeline; web + auth + billing)
   - **Yes** → `REGRESSION` candidate.
   - **No** → continue.

3. **Directly affects a user?** (SDK, public API, user-visible app flow, external-integrator-observable contract)
   - **Yes** → `REGRESSION` candidate.
   - **No** → `REPO_LOCAL` (integration).

#### Examples

| Test description                                                          | Outcome                                       |
| ------------------------------------------------------------------------- | --------------------------------------------- |
| Web login → auth token → api request validation (3 services, user flow)   | `REGRESSION`                                  |
| SDK call → api rule lookup → local decision (touches SDK)                 | `REGRESSION`                                  |
| Worker event → analytics API within 30s (4 services)                      | `REGRESSION`                                  |
| Tenant A's request must never see tenant B's data                         | `REGRESSION` (a tenancy invariant)            |
| ORM soft-delete + `is_active` filter                                      | `REPO_LOCAL` integration in `api`             |
| Rule evaluator decision for synthetic rule + request                      | `REPO_LOCAL` integration in `worker`          |
| Function extracts the tenant key from a JWT                               | `REPO_LOCAL` unit test                        |
| jq expression in a hook script handles empty stdin                        | `REPO_LOCAL` bash test in `hooks/`            |

For test markers and profile selection (`regression.profiles`), see `~/.claude/aif-references/regression-markers.md`.

## Output

### Short form — common path

When Step 1 is `NO_UPDATE` AND Step 2 is `NO_TEST` / `EXTEND_EXISTING` / `REPO_LOCAL`:

```
feature-prep: NO_UPDATE; <Step 2 outcome with brief location>. proceed.
```

### Full form — anything involving NEW_ENTRY, NEW_PRIMITIVE, EDIT_EXISTING, or REGRESSION

```
Feature: <one-line description>

Step 1 — spec registry:
  Outcome: NO_UPDATE | EDIT_EXISTING | NEW_ENTRY | NEW_PRIMITIVE
  <NO_UPDATE>     Reason: <pure bug fix / refactor / dev-tooling / test-only / no registry configured>
  <EDIT_EXISTING> Existing entry ID: <ID>; what changes: <one-line>.
  <NEW_ENTRY>     Kind: capability | invariant
                  Area: <area from your registry's taxonomy>
                  Proposed ID: <per your registry's ID scheme>
                  Draft entry: <yaml block>
                  Action: open spec-only PR against the registry's repo before any implementation.
  <NEW_PRIMITIVE> Stop. Surface to user: candidate area, name, what it owns, why no existing area fits.

Step 2 — test placement (one outcome, OR REGRESSION + REPO_LOCAL together):
  Outcomes: NO_TEST | EXTEND_EXISTING | REPO_LOCAL | REGRESSION
  <REGRESSION>      Mandatory if Step 1 = NEW_ENTRY. Trigger: <2+ services / user-facing>.
                    Test scenario: <one-line>. Marker: <suite convention, e.g. @pytest.mark.capability("<ID>")>
```

## Rationalizations (and rebuttals)

| You'll be tempted to think…                                             | Why it's wrong                                                                                                                            |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| "It's just a small change, skip the spec"                               | If it's a new contract surface, "small" doesn't matter — the spec IS the contract. Un-cataloged means undiscoverable.                     |
| "I'll add the spec entry after the implementation lands"                | Then the entry status is wrong (`implemented` with no verifying test) and the registry stops being a leading indicator. Spec PR first; cheap. |
| "The regression suite already has 5 similar tests, one more won't hurt" | Wrong axis. Each test is judged against the rubric, not the bucket.                                                                       |
| "I'll add the regression test in a follow-up PR"                        | The promotion rule pegs the entry at `planned` until the test lands.                                                                      |
| "This is technically a refactor so no spec entry"                       | If external behavior changes (timing, error shape, response field), it's a contract change.                                               |
| "Renaming the entry ID is cleaner"                                      | IDs are permanent. Retire + add new; never renumber.                                                                                      |

## Red flags

- You're 30 minutes into implementation and just realized the feature crosses two services. **STOP.** Run Step 1 now.
- Your spec PR diff includes anything besides the registry file (or its companion rules doc, if changing the rules). Split it.
- You drafted a `NEW_PRIMITIVE` autonomously. STOP — surface to the user.
- The new test fits the regression rubric but you're putting it in repo-local "to avoid the matrix." Wrong tradeoff.
- You're tagging a test with an entry ID that doesn't exist in the registry. Orphan markers go red.
- You produced the full ceremony for a project with neither `org.spec_registry` nor `regression.repo` configured. One line was the right answer.

## Verification

This skill produces a decision, not code. Done when:

- [ ] Config checked: `org.spec_registry` and `regression.repo` presence noted
- [ ] One of the four Step 1 outcomes is selected with reasoning
- [ ] One or two Step 2 outcomes are selected with concrete location (test path or repo)
- [ ] If `NEW_ENTRY`: user has confirmed area, kind, ID, and entry text BEFORE any spec PR is opened
- [ ] If `NEW_PRIMITIVE`: user has been asked; no autonomous drafting
- [ ] If `REGRESSION`: scenario is named in one line and references the marker
- [ ] If short-form output is used: Step 1 is `NO_UPDATE` AND Step 2 is in the trivial bucket

## Worked example (illustrative — a registry using a `KIND-AREA-NNN` id scheme)

```
Feature: batch_mode=true must never schedule every processor product-wide;
         only processors referenced by rules matching the request's action.

Step 1 — spec registry:
  Outcome: NEW_ENTRY
  Kind: invariant   (negative claim)
  Area: DET         (this registry's detection/processing area)
  Proposed ID: INV-DET-001
  Draft entry:
    - id: INV-DET-001
      kind: invariant
      area: detection
      title: "batch_mode=true is scoped per (action, product), never product-wide"
      description: >
        With batch_mode=true, the worker must only schedule processors whose
        output keys are referenced by rules that match the request's
        action. Prevents signal contamination across actions.
      doc: core-foundations/processing-model.md#processor-pipeline
      status: planned
      owner: eng
  Action: spec-only PR against the registry's repo; confirm with user.

Step 2 — test placement:
  Outcome: REGRESSION + REPO_LOCAL

  REGRESSION (mandatory; flips status to implemented):
    Scenario: send a request with batch_mode=true and a rule bound to action A;
              assert no processor for action B fires.
    Trigger: worker + rules index + api (negative-path invariant).
    Marker: @pytest.mark.capability("INV-DET-001")

  REPO_LOCAL (recommended fast-feedback in the worker repo):
    Level: integration
    What it covers: the scheduler returns the action-scoped subset
                    for a synthetic rule + request, in-process.
```

## Anti-patterns

- Auto-creating the spec PR without user confirmation
- Bundling spec edits with feature work (spec PRs are pure)
- Putting fine-grained correctness in regression "to be thorough"
- Skipping the regression test on a `NEW_ENTRY`
- Renumbering an existing ID
- Inventing a new ID scheme or taxonomy area instead of following the registry's existing one
- An entry without a `doc:` link to a real anchor in a real arch doc
- Confusing `EDIT_EXISTING` (clarification) with widening contract (treat as `NEW_ENTRY`)
- Running the full ceremony when no registry and no regression suite are configured
