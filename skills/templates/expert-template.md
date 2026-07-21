---
name: <expert-name>                # kebab-case, e.g. react-frontend, dynamodb-access, payments-domain
domain: <human-readable domain>    # e.g. "React frontend", "DynamoDB data access", "Payments"
summary: <one line — what this expert knows and the kind of change it matters for>
applies_to:                        # globs, relative to repo root. THE activation key: an expert
  - <glob>                         # is injected when a change touches a path matching any glob.
  - <glob>                         # (Also the future compile key for path-scoped Copilot/Cursor rules.)
sources:                           # provenance — where this curated context was distilled from
  - <path-or-url to the docs/code this expert summarizes>
signal:                            # RESERVED — how to validate behavior in this domain at runtime.
  status: reserved                 # Not yet enforced; a later release wires this into the pipeline.
  validate: <command or description, e.g. "pnpm --filter web test">
---

# <Domain> expert

<!--
  An expert is CURATED, DISTILLED context for one domain — not a doc dump.
  It exists to spend the agent's token budget well: it is injected ONLY when a
  change touches `applies_to`, so keep it dense and load-bearing. If a fact is
  true everywhere, it belongs in workspace-CLAUDE.md or conventions.md, not here.
  Target: what a strong engineer new to THIS domain would need to not make the
  three most common mistakes. Cite `sources:` rather than reproducing them.
-->

## What matters in this domain

<The 5-15 load-bearing facts: the architecture, the contracts, the invariants
that a change in this domain must respect. Dense prose or tight bullets.>

## Conventions specific to this domain

<Naming, layering, patterns that apply HERE and aren't in the global conventions.>

## Common mistakes (and the right move)

- <mistake> → <correct approach>
- <mistake> → <correct approach>

## Where to verify

<How to check that a change here actually works — the tests, the local run, the
signal. Mirrors the reserved `signal:` field above; state it in prose until the
runtime wiring lands.>
