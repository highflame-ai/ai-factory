---
name: threat-model
description: Generate a STRIDE threat model from a spec, RFC, or feature description — enumerate assets, actors, trust boundaries, and data flows, walk STRIDE per element, rate what's credible, and emit a mitigations punch list as a reviewable artifact stored next to the spec. Use before implementing anything auth-adjacent, tenant-crossing, or that adds a new external surface.
argument-hint: "<spec path | REQ-id | feature description>"
---

# Threat-model — STRIDE pass on a design before it's built

## Ethos

!`sh .aif/partials/ethos-include.sh 2>/dev/null || sh ~/.claude/skills/partials/ethos-include.sh`

## Input

$ARGUMENTS

## Overview

The cheapest place to kill a vulnerability is the design. This skill turns a spec into a structured threat model: what are the assets, who touches them across which trust boundaries, and what does STRIDE say about each crossing. Output is an artifact reviewers and `/architect` can hold the implementation against — not a compliance checkbox.

This complements, not replaces: `/grill-feature` (adversarial design review, broader than security), `@security-reviewer` (audits written code), and `/ship`'s pre-merge fan-out. Run this BEFORE implementation; run those DURING and AFTER.

## When to use

- A spec/RFC touches authn/authz, tenant isolation, secrets, or money
- A new external surface (endpoint, webhook, upload, integration) is being designed
- `/grill-feature` or `/architect` flags security-sensitive scope
- A reviewer asks "has this been threat-modeled?"

**Skip** for: pure-internal refactors with no new data flow, and UI-only changes behind existing contracts.

## Process

### Step 1 — Read the actual spec

Resolve the input: a file path; a REQ id (`.aif/specs/REQ-<id>-*/requirement.md`); an entry in `org.spec_registry` (when configured); or a prose description from the user. Read it fully, plus the auth conventions that constrain it: `~/.claude/aif-references/jwt-checklist.md` (token archetypes) and `~/.claude/aif-references/multi-tenancy-checklist.md` / `tenancy.keys` in `.aif/config.yml` (skip tenancy analysis with a note when unconfigured — and ask whether the system is genuinely single-tenant).

If the spec doesn't say where data comes from or who calls what, STOP and get answers — a threat model over guessed data flows is fiction (ethos #1, #2).

### Step 2 — Map the system

Enumerate, as tables in the artifact:

- **Assets** — data/capabilities worth attacking (credentials, tenant data, tokens, quotas, audit logs)
- **Actors** — humans and services, with their token archetype per the jwt-checklist
- **Trust boundaries** — every place identity or privilege changes (client→edge, service→service, service→store, tenant→tenant)
- **Data flows** — a mermaid diagram of who sends what across which boundary

### Step 3 — Walk STRIDE per boundary crossing

For each data flow that crosses a trust boundary, ask all six:

| Letter | Question against THIS flow |
|---|---|
| **S**poofing | Can the caller be someone else? What proves identity here? |
| **T**ampering | Can the payload/state be altered in flight or at rest? |
| **R**epudiation | Would we know who did it? Is the action logged with actor + tenant? |
| **I**nformation disclosure | What leaks on error, in logs, in timing, across tenants (`tenancy.keys` scoping)? |
| **D**enial of service | What's unbounded — payload size, fan-out, retries, quota? |
| **E**levation of privilege | Can a lower-privilege token reach a higher-privilege path? |

Then try to refute each candidate threat before recording it (ethos #7): a threat that an existing, verified control already kills is recorded as "mitigated by <control>" with a pointer, not raised as a finding. "I couldn't find a control" and "a control exists" are different claims — say which.

### Step 4 — Rate and prescribe

For each surviving threat: severity (what's lost) × likelihood (attacker effort), a concrete mitigation, and WHERE it lands — a spec change (redesign), a task for `/architect` to carry, or a test the implementation must ship with.

### Step 5 — Write the artifact

Save next to the spec when one exists — `.aif/specs/REQ-<id>-*/threat-model.md` — else `${TMPDIR:-/tmp}/threat-model-<slug>.md` (resolve the path in shell first). Structure: system map (Step 2 tables + diagram) → threat table (id, STRIDE letter, flow, threat, refutation attempted, severity, mitigation, lands-in) → punch list ordered by severity. Tell `/architect` to treat the punch list as constraints, and tag the follow-up review for `@security-reviewer`.

## Failure modes to avoid

1. Modeling the system you imagine instead of the one specced — every flow in the diagram must trace to a spec sentence or a user answer (ethos #1).
2. Recording every theoretical threat — an unrefuted-but-implausible flood buries the three real ones (ethos #7).
3. Prescribing "validate input" as a mitigation — mitigations name a mechanism, a place, and a test.
4. Treating the artifact as done-once — a spec revision that adds a flow invalidates the model; note that in the artifact header.
