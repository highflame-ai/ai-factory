---
name: expert
description: Create or update a domain expert — a curated, path-scoped context bundle distilled from the org's own docs and code, injected only when a change touches its domain. Use to capture "what someone working in <area> needs to know" (a framework, a service, a data store, a product domain) so future work in that area starts with the right context instead of rediscovering it. Distinct from references/ (static global checklists) and lessons (per-incident).
argument-hint: "<domain or area> [--from <doc-path-or-url>]"
---

# Expert — curate path-scoped domain context

## Ethos

!`sh .aif/partials/ethos-include.sh 2>/dev/null || sh ~/.claude/skills/partials/ethos-include.sh`

## Context

!`cat .aif/context/conventions.md 2>/dev/null || echo "No conventions doc found — run /init first"`

## Input

$ARGUMENTS

## What an expert is (and is not)

An **expert** is dense, distilled context for ONE domain, stored at
`.aif/experts/<name>.md`, that the toolkit injects into a task ONLY when the
change touches that domain (matched by the expert's `applies_to` globs). It is
how the agent gets the right domain context without paying for it on every
unrelated task — context engineering, not a doc dump.

| Surface | Scope | Loaded | Authored from |
|---|---|---|---|
| `workspace-CLAUDE.md` | whole platform | always | facts true everywhere |
| `references/*.md` | a cross-cutting concern | on skill demand | a checklist |
| **expert** | **one domain** | **when a change touches its paths** | **the org's docs + code** |
| lesson | one past surprise | relevance-ranked in `/review` | an incident |

If a fact is true across the whole platform it belongs in `workspace-CLAUDE.md`;
if it's a reusable checklist, a reference. An expert earns its place by being
domain-specific AND path-scoped.

## Prerequisites

`.aif/` must exist (run `/init` first). Experts live at `.aif/experts/`; create
the directory if this is the first expert.

## Process

### Step 1 — Scope the domain and its paths

Establish two things before writing anything:

1. **The domain** — from `$ARGUMENTS` or by asking: a framework (React), a data
   store (DynamoDB), a service, or a product area (Payments). One domain per
   expert; if the ask spans two, make two.
2. **The paths it governs** — the `applies_to` globs. Derive them from the repo
   layout (`.aif/config.yml` `repos:`, the actual directory tree), not a guess.
   These globs are load-bearing twice over: they decide when the expert
   activates, and they are the future compile key for path-scoped rules in
   other assistants. Verify each glob matches real files:

```sh
# confirm a candidate glob actually matches tracked files (repeat per glob)
git ls-files 'web/src/**/*.tsx' | head -5
```

If a glob matches nothing, fix it — an expert that never activates is dead weight.

### Step 2 — Gather the source material (source-driven)

Read the authoritative material, don't summarize from memory (ethos #1): the
`--from` doc(s), the domain's own README/ADRs, and a representative slice of the
actual code in the `applies_to` paths. Record every source in `sources:` for
provenance — an expert whose claims can't be traced is a liability.

### Step 3 — Distill, don't dump

Write `.aif/experts/<name>.md` from `~/.claude/skills/templates/expert-template.md`
(or `.aif/templates/expert-template.md` inside a worktree). The bar: what a
strong engineer new to THIS domain needs to avoid the three most common
mistakes. Dense and load-bearing — every line should change what an agent does.
Cite sources rather than reproducing them. If you're pasting a doc, you're not
distilling.

Fill `signal:` with how behavior is verified in this domain (the test command,
the local run). It is `status: reserved` — not yet enforced by the pipeline —
but capturing it now makes the expert complete and readies the runtime wiring.

### Step 4 — Verify activation

Confirm the expert will actually fire and reads cleanly:

```sh
ls .aif/experts/
```

State plainly: which paths activate this expert, and one example change that
would (and one that wouldn't). If updating an existing expert, note what changed
and why.

## Updating an existing expert

Same file, same process — re-distill from current sources. Experts are living:
when a domain's architecture shifts, or a lesson recurs in one domain enough to
be structural, fold it into that domain's expert. Prefer updating an expert over
adding a fourth bullet to the global conventions.

## Failure modes to avoid

1. **Doc dump instead of distillation** — the whole point is token economy; a
   pasted 400-line doc spends the budget it was meant to save.
2. **Globs that match nothing** (or everything) — verify with `git ls-files`; a
   dead expert misleads, a too-broad one is just always-on context with extra steps.
3. **Global facts in an expert** — those belong in `workspace-CLAUDE.md`; keep
   experts domain-specific.
4. **Unsourced claims** — record `sources:`; an expert is only as trustworthy as
   its provenance (ethos #1).
5. **Set-and-forget** — a stale expert is worse than none; update it when the
   domain moves.
