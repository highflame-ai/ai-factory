---
name: grill-feature
description: Adversarial design review for architectural / cross-service / contract-touching work. Interviews the user one question at a time, anchored in whatever design sources exist (`.aif/context/architecture.md`, ADRs under `org.adr_dir`, the spec registry at `org.spec_registry`, per-repo CLAUDE.md), surfacing ambiguity in scope, contract, multi-tenancy, auth, observability, and migration order BEFORE implementation starts. ONLY use when the change (a) crosses ≥2 services, (b) introduces or modifies a platform invariant or capability, (c) touches a shared contract (authz schema, JWT claims, multi-tenancy boundary, event/span shape, public API), (d) proposes a new domain concept, or (e) is a new service / new repo / rewrite of an existing service. For everyday features use /feature-prep instead.
---

# Grill-feature — adversarial design review for architectural work

## Overview

`/feature-prep` is the everyday checklist (spec registry? where do tests live?). This skill is the **forcing function for the rarer, higher-stakes changes** — the ones where ambiguity costs weeks downstream. It interviews relentlessly, anchored in your project's design sources, before any code is written. Decisions get captured as either (a) a spec-registry entry draft, (b) a new ADR draft under `org.adr_dir`, or (c) a captured assumptions block.

**Most features don't need this.** Default to `/feature-prep`. This skill earns its keep only when ambiguity is genuinely structural.

**Every anchor is optional.** `.aif/context/architecture.md`, the ADR directory (`org.adr_dir`), and the spec registry (`org.spec_registry`) each sharpen the grilling when present — but the interrogation method is the point. When an anchor is missing, say so, grill anyway, and mark affected answers "no current doc — proposing convention".

## When to use

Run this skill when ANY of:

- **Crosses ≥2 services** (api + worker + web; auth + billing; etc.)
- **Introduces or modifies a platform invariant or capability** (the spec-registry change is more than cosmetic)
- **Touches a shared contract**: authorization schema, JWT claims, token issuance, multi-tenancy boundary (the semantics of your `tenancy.keys`), event/span shape between services, public API surface, SDK signature
- **Proposes a new domain concept** (a noun nobody on the team uses yet — "principal context", "delegated decision", etc.)
- **New service, new repo, or rewrite of an existing service**

**Do NOT run for** (use `/feature-prep` instead):

- Single-repo features that don't change a shared contract
- Bug fixes that restore existing-spec behavior
- Internal refactors
- New endpoints under an existing, well-worn pattern
- Dev tooling, hook, skill, or settings changes

If unsure: ask the user *"this feels everyday-checklist not architectural-grilling — should I use `/feature-prep` instead?"* and only proceed on explicit confirmation.

## The design-source glossary (in priority order)

Before grilling, load the relevant slice of the glossary. **Read these, do not paraphrase from memory** — drift is the whole reason this skill exists. Each source is optional; load what exists, name what doesn't.

| Source                                                                     | Load when…                                                                             |
| -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `.aif/context/architecture.md`                                             | Always, if present — service map, auth contract, multi-tenancy rules                   |
| Spec registry at `org.spec_registry` (from `.aif/config.yml`)              | If configured — the load-bearing spec; grep for the area(s) the work touches           |
| ADRs under `org.adr_dir`                                                   | If configured — list and skim titles; read in full any ADR in the area the work touches |
| Other architecture docs in the same repo as the registry/ADRs              | When the work touches that area (foundations, cross-cutting concerns, runbooks)        |
| Per-repo `CLAUDE.md` of each touched repo                                  | Always for each touched repo                                                            |
| Nested `CLAUDE.md` in touched subtrees                                     | When the work lands inside that subtree                                                 |
| Authorization policy/schema files (if your org uses a policy engine, e.g. Cedar) | When the work changes principals, actions, resources, or request context          |
| `~/.claude/aif-references/jwt-checklist.md`                                       | When the work touches JWT issuance, validation, claims, or any auth surface            |
| `~/.claude/aif-references/multi-tenancy-checklist.md`                             | When the work touches DB queries, cache keys, or any handler that derives identity     |
| `~/.claude/aif-references/migration-safety-checklist.md`                          | When the work includes a schema or data migration                                       |
| MCP docs tools (`mcp__<namespace>__docs_list` / `docs_read`, namespace from `mcp.namespace`) | When configured and the live arch docs are authoritative and no local file exists |

If a discipline doc exists in the area (threat-model coverage, technique coverage, etc.), that's a glossary source too — read it.

**Never grill on memory of how the platform works.** Open the file. Quote the line. Drift between what's documented and what you remember is *exactly* what this skill exists to catch. And when NO doc covers a question, that's a finding in itself — recommend a convention and label it as proposed.

## Process

### Step 0 — Decide whether to proceed

Restate the user's ask in one sentence. Then ask yourself the gate questions:

```
Does this cross ≥2 services?               YES / NO
Does this touch a shared contract?         YES / NO
Does this introduce/modify an invariant?   YES / NO
Does this propose a new domain concept?    YES / NO
Is this a new service/repo or rewrite?     YES / NO
```

If ALL are NO → say so, recommend `/feature-prep`, exit. Do not grill anyway.

If any are YES → state which gate(s) qualified, and continue.

### Step 1 — Load the glossary slice

Identify the platform areas touched (identity, authorization, tenancy, observability, …, per your registry's taxonomy if one exists). If `org.spec_registry` is configured, grep it for those areas and list every `id` + `title` + `status` you find:

```bash
grep -nE "^[[:space:]]*- id: " <org.spec_registry path>
```

If `org.adr_dir` is configured, list the ADRs:

```bash
ls <org.adr_dir>/*.md
```

Open and read in full: every ADR whose title overlaps the work, every CLAUDE.md in a touched repo or subtree, every checklist in the table above whose trigger fires. **Cite file:line when answering grill questions** — vague answers from memory defeat the point. If neither registry nor ADRs exist, state that plainly and proceed; your recommendations will lean on the checklists, the code, and first principles.

### Step 2 — Grill, one question at a time

Walk down the decision tree. For each question:

1. State the question.
2. Give your **recommended answer**, grounded in a glossary citation (or explicitly marked "no current doc — proposing convention").
3. Name the **branches** (what changes if the answer differs).
4. **Wait for the user.** Do not batch.

If a question can be answered by reading code or a doc, read it instead of asking.

The default question sequence — adapt order to the work, skip irrelevant questions, add project-specific ones as they surface:

#### A. Scope and boundary

1. **What's the user-visible promise (or prohibition) in one sentence?** This is the title of the eventual capability/invariant entry. If you can't write it, the scope is fuzzy.
2. **Which platform area does this belong to?** (Per your registry's taxonomy, if configured.) If more than one, why? Multiple areas often = a missing decomposition.
3. **What is explicitly OUT of scope?** Capture as "deferred", with the trigger that would bring it back in.
4. **Which existing capability/invariant does this extend, edit, or supersede?** Cite the ID (when a registry exists). If it supersedes, what's the retirement plan for the old entry?

#### B. Contract surface

5. **What is the request shape across each service boundary?** Be specific — field names, types, optionality. Where is this contract written today? (Proto? OpenAPI? Authz schema? An ad-hoc struct?)
6. **What is the response / outcome shape, including error modes?** Name each error, its trigger, its HTTP/gRPC status, its propagation through downstream services.
7. **Is this a synchronous call, an async event, or both?** If async, what's the eventual-consistency window, and who owns measuring it?
8. **What versioning story do we promise?** If the contract changes again in 6 months, how do we know who breaks?

#### C. Identity, authz, multi-tenancy (almost always relevant)

9. **What identity is the actor, and where does the tenant key come from?** (First key in `tenancy.keys`, e.g. `account_id`.) The convention is: from the JWT, not headers — confirm against your docs. See `~/.claude/aif-references/jwt-checklist.md` and `~/.claude/aif-references/multi-tenancy-checklist.md`.
10. **What identity is the resource owner, and where does the scoping key come from?** (Remaining `tenancy.keys`, e.g. `project_id`.) Same gate. If a tenancy key is missing from a query, cache key, or filter, the design is wrong before any code is written.
11. **Which authorization action covers this?** If your org uses a policy engine (e.g. Cedar), does the existing schema already model it, or are we adding an action / principal / resource type? A schema addition is itself a contract change (see Section B).
12. **Cross-tenant blast radius**: write the worst-case prompt — *"can tenant A see, modify, or trigger anything in tenant B?"* — and show why the answer is no.

#### D. Observability and evidence

13. **What spans / events does this emit?** What's the schema? Does your observability pipeline know how to read them? If the event shape is new, this IS a contract change (see Section B).
14. **What does a passing run look like in your telemetry store?** What's a failing run? Could the next on-call engineer diagnose a regression from spans/events alone?
15. **What gets audited?** If a request is denied, where does the evidence live, and what's the retention?

#### E. Data and migrations

16. **Does this touch any table?** If yes — additive (safe), backfill (needs plan), drop (needs deprecation cycle)? See `~/.claude/aif-references/migration-safety-checklist.md`.
17. **Migration ordering across services**: which migration must land FIRST so the next service's deploy doesn't 500? Capture as an ordered sequence.
18. **Delete semantics**: if your platform convention is soft-delete (e.g. an `is_active` column), is the new behavior consistent with it? Hard deletes against a soft-delete convention are an anti-pattern.

#### F. Verification

19. **What's the end-to-end test that proves this works?** If a spec-registry entry is involved, this is the test that flips it from `planned` to `implemented`. Write its one-line scenario. (Goes in `regression.repo` if configured; repo-local otherwise — per `/feature-prep` Step 2.)
20. **What's the repo-local test that gives fast feedback?** (Often complements the end-to-end test.)
21. **How do we know we're done?** Specifically — what query against your telemetry store / database / test harness returns the expected answer?

#### G. Rollout and rollback

22. **What's the rollout order across repos?** Which PR merges first, which second? Capture dependencies — "web PR depends on api PR landing AND deploying to the shared dev environment" (`environments.dev.name`, when configured).
23. **What's the rollback plan if the first deploy is bad?** Specifically — feature flag? Revert PR? Manual DB step?
24. **What's the dev → staging → prod gate?** What signal would block promotion?

### Step 3 — Capture decisions

Decisions land in ONE of three places. Pick the right one:

| Outcome                   | When                                                                                   | Where                                                                                              |
| ------------------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Spec-registry entry draft | New capability/invariant is the cleanest summary of the promise/prohibition             | Draft the entry; hand to `/feature-prep` Step 1 for the spec-only PR. (Requires `org.spec_registry` — otherwise capture as assumptions.) |
| New ADR draft             | Decision is about *how* to build it (architecture, sequencing, alternatives weighed)     | Draft into `<org.adr_dir>/NNNN-<slug>.md` following the existing ADR template. (Requires `org.adr_dir` — otherwise capture as assumptions.) |
| Assumptions block         | Decisions are scoped to the implementation PR(s); no ADR or spec entry warranted — or the project has no registry/ADR home | Capture as "ASSUMPTIONS" block to include in the PR description                                     |

You can produce more than one: typically a `NEW_ENTRY` for the registry PLUS an ADR for the *how* PLUS assumptions for the rest.

### Step 4 — Hand off

State explicitly which skill to invoke next:

```
Grilling complete. Decisions captured:
  - spec-registry entry: <ID> (draft above)
  - ADR: <org.adr_dir>/NNNN-<slug>.md (draft above)
  - <N> assumptions captured for PR description

Next:
  - Run /feature-prep to open the spec-only PR for <ID>
  - Then /incremental-implementation to land the work in vertical slices
  - Run @cross-repo-impact if you haven't enumerated all affected repos yet
```

## What good grilling looks like

A grill question is **specific, grounded, and resolves a real branch**.

- **Bad**: "How does auth work?" (vague, ungrounded, has no branch)
- **Good**: "`architecture.md:177` says the tenant id is always derived from JWT claims, never headers. Your design currently passes `x-tenant-id` from the web app. Branch: (a) drop the header and derive from the JWT in the api service, or (b) change the rule. (a) is consistent with the documented contract — recommend (a). Confirm?"

A grill question that the user can answer with "yes, you decide" was the wrong question — pick something they actually need to weigh.

## Cross-cutting gotchas the grilling must catch

- **A new service-to-service call that skips your internal service-auth mechanism** (mTLS, shared-secret header, signed tokens — whatever your platform uses) IS a security regression, not a wiring detail. Find the mechanism in the architecture doc and confirm the new call uses it.
- **Single-domain email or org checks** — orgs accumulate legacy domains and aliases. A check hardcoding one domain is a bug waiting; confirm the full allowed set against the docs.
- **Hardcoded ID allowlists** — `if id in [...]` is an anti-pattern; the right fix is a universal rule + tests. Push back if the design proposes one.
- **Bundling spec edits with feature work** — spec PRs are PURE. If grilling produces a registry entry, that lands ALONE before implementation.
- **`NEW_PRIMITIVE`** — never draft one autonomously. If the work doesn't fit the registry's existing taxonomy, STOP and surface to the user with a name proposal and justification.
- **Database migration** — locking, backfill strategies, NULL handling all need `@migration-analyzer` BEFORE merge; mention it in the handoff.

## Rationalizations (and rebuttals)

| You'll be tempted to think…                                          | Why it's wrong                                                                                                                |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| "I know how this platform's auth works, I don't need to open the file" | Drift between memory and the doc IS what this skill exists to catch. Open the file. Cite the line.                          |
| "This question is too granular, skip it"                             | If the question maps to a real branch, it's not too granular. Granularity is the point.                                       |
| "I'll grill all 24 questions"                                        | No — adapt to the work. Half are usually irrelevant. Skip them out loud so the user knows you considered them.                |
| "I'll batch the questions to save time"                              | One at a time. Each answer constrains the next; batching loses that.                                                          |
| "The user said 'just do it', I'll skip grilling"                     | If the gate questions in Step 0 all said YES, the user will thank you later for the 10-minute grill. Push back politely.      |
| "No architecture.md, no ADRs — nothing to grill against"             | The anchors sharpen the grill; they don't gate it. Grill from the code, the checklists, and first principles, and label proposals as proposals. |
| "I'll let the user decide every question, no recommendations"        | Wrong. Grilling without recommendations is interrogation. Always recommend with a citation; let them override.                |
| "I'll capture decisions in my head and write them up at the end"     | They'll be lost. Capture as you go; Step 3 just decides WHERE they land.                                                      |

## Red flags

- You've asked 5 questions without citing a single file (and without saying "no current doc"). You're guessing, not grilling.
- The user has answered "yes, you decide" twice in a row. Your questions aren't real branches; sharpen them.
- You're 20 questions in and the work was a single-repo bug fix. Step 0 should have rejected this — apologize, exit, point to `/feature-prep`.
- A grill produced no spec-registry entry, no ADR, no assumptions block. Either the work was too small (Step 0 failure) or you didn't capture as you went.
- You autonomously drafted a `NEW_PRIMITIVE`. Stop. Surface to the user.
- You drafted a spec entry that bundles feature work into the same PR. Split it.

## Verification

Done when:

- [ ] Step 0 gate questions answered and ≥1 said YES (else exited to `/feature-prep`)
- [ ] Glossary slice loaded — every relevant ADR and CLAUDE.md that exists *read*, not paraphrased; missing anchors named
- [ ] Every grilled answer cites a file:line (or explicitly states "no current doc — proposing convention")
- [ ] Decisions captured in spec-registry entry draft, ADR draft, and/or assumptions block
- [ ] Hand-off names the next skill(s) to invoke and the order

## Anti-patterns

- Grilling on memory, not on the docs
- Batching questions
- Asking without recommending
- Asking questions with no real branch
- Skipping `Step 0` and grilling everyday work
- Refusing to grill because the anchors are missing
- Drafting `NEW_PRIMITIVE` autonomously
- Bundling spec edits with feature edits
- Capturing decisions in conversation only, never to a file or PR description
