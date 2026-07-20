---
name: deprecate
description: Removes an old API, field, capability, or service across every repo declared in `.aif/config.yml` `repos:` in safe stages — announce → stop new uses → migrate existing → delete. Use when ripping out a legacy endpoint, removing a column, retiring a capability, or replacing X with Y. Pairs with `cross-repo-impact` to find every caller and `feature-prep` to retire the spec-registry entry.
---

# Deprecate — remove old code safely

## Overview

Removing code is harder than adding it because consumers in other repos / external integrators depend on it. This skill sequences the removal so nothing breaks mid-flight. The default is **slow** — 2+ PRs over multiple days — because that's the safe shape.

## When to use

- Removing an API endpoint
- Removing a DB column
- Retiring a spec-registry entry (`status: retired`) — if your org tracks capabilities in `org.spec_registry`
- Replacing X with Y where X is in `main` and shipped
- Dropping an authorization action or principal kind from your policy schema
- Removing a detector / analyzer component (and the signal keys it emits)

**Don't use** for:

- Removing internal helpers with no external consumers — just delete
- Code that hasn't shipped yet — just delete
- Bug fixes (that's not deprecation)

## Process

### Step 0 — name the scope

Write down:

- **What's being removed** (one line)
- **Replacement** (the new thing, if any) or "no replacement; this is no longer needed"
- **Why** (compliance / new design / unused / consolidating with X)

If there's no replacement and consumers exist, you owe them a migration path before deleting. If nothing depends on it, this is a one-PR delete; skip the rest.

### Step 1 — find every consumer

Delegate to `cross-repo-impact`:

> _"Have cross-repo-impact find every caller of `<endpoint/field/symbol>` across every repo in `.aif/config.yml` `repos:`. I'm planning to deprecate it."_

The agent returns a punch list of files in every repo that references the symbol. Print the list; you'll work down it. (If `repos:` lists only this repo — or the config is absent — the search is repo-local; say so and continue.)

**If your org tracks capabilities** (`org.spec_registry` is set): also check the registry file — the entry being retired needs `status: retired` per `/feature-prep` Step 1 (`EDIT_EXISTING` outcome). If `org.spec_registry` is absent, skip this and every later capability step; note the skip once.

### Step 2 — announce (PR 1: deprecation marker)

Mark the old thing as deprecated, but **don't break anything**. The PR that ships first:

| Artifact             | Mark with                                                                                      |
| -------------------- | ---------------------------------------------------------------------------------------------- |
| Go function / type   | `// Deprecated: use NewThing instead. Remove after <date>.` (gofmt-aware comment)              |
| Python function      | `@deprecated` decorator OR docstring `.. deprecated:: <date>`                                  |
| HTTP endpoint        | Response header `Deprecation: <date>` + `Link: <new-endpoint>; rel="successor-version"`        |
| DB column            | No marker (the migration that drops it lands later); add a code comment near every read/write  |
| Spec-registry entry  | Edit the `org.spec_registry` file: `status: retired` + one-line `retired_reason` (per `/feature-prep`); skip if `org.spec_registry` unset |
| Authorization action | Mark in the policy schema; do not yet remove                                                   |

Verification at this stage: builds still pass, no consumer is broken, deprecation surfaces in IDE / API responses.

### Step 3 — stop new uses (PR 2 onwards: migrate consumers)

Now that the deprecation is shipped and visible, walk the cross-repo punch list. One PR per consumer (or one bundled PR if scope is small):

- Replace the call with the new thing
- Verify locally + push
- Reference the deprecation PR in each consumer's PR description

For DB columns: stop writing to it first, then stop reading, then drop. Each step is its own migration / PR.

For HTTP endpoints: external integrators may still hit the old one — keep it routed but log a deprecation event so you can see who's still using it.

### Step 4 — wait

If external consumers exist (SDK users, customer integrations), wait the announced deprecation period. For internal-only deprecations, this can be hours; for SDK-affecting changes, it's typically a release cycle or a fixed grace period.

You can verify "no one's calling this anymore" via your org's MCP server (`mcp__<namespace>__*` tools, `<namespace>` from `mcp.namespace`):

- API endpoint → the observability/events tool filtered to the endpoint, over the last N days
- DB column → the DB query tool if the table is small; check for non-NULL counts that should be zero

If no MCP server is configured, say so and use local alternatives: production dashboards, access logs (`kubectl logs` if available), or a query run by someone with DB access. Never assume zero traffic without evidence.

### Step 5 — delete (final PR)

Remove:

- The deprecated function / type / endpoint
- The DB column (via migration; see `~/.claude/aif-references/migration-safety-checklist.md` — DROP COLUMN is two migrations: stop reading first, drop second)
- The authorization action / principal from the policy schema
- The detector / analyzer + its signal keys (keys silently disappear from new events; old data preserved)

Update:

- The spec-registry entry was already `status: retired` from Step 2; no further change unless adding a `removed_in: <version>` annotation (skip if `org.spec_registry` unset)
- CHANGELOG / release notes

Subject per your commit convention — `org.commit_prefix_regex`, defaulting to Conventional Commits, e.g. `refactor: remove <thing>` (or `feat!: remove <thing>` if it breaks an API). See `~/.claude/aif-references/commit-prefix-check.md`.

### Step 6 — verify

After the delete merges:

- Observability overview (MCP tool if configured, dashboards otherwise) — no error rate spike (would mean a consumer slipped through)
- Events/traffic filtered to the old endpoint — should be zero
- Build/test green across all touched repos
- For DB drop: confirm the column is gone (MCP describe-table tool, or `\d <table>` via psql / your DB client)

If a consumer slipped through: revert Step 5, re-deprecate, find the missing consumer, repeat.

## Gotchas

- **Spec-registry entries are durable** (if your org tracks capabilities). A retired entry stays in the registry forever. Never delete; never reuse the ID.
- **Authorization actions are sticky.** Dropping an action from a policy schema invalidates any stored policy that references it. Audit stored policies before drop.
- **Signal keys outlive their emitter.** Removing a detector/analyzer stops the keys appearing in new events, but historical rows still have them — downstream queries should tolerate missing keys.
- **DB columns.** DROP COLUMN takes an exclusive lock — short, but on a busy table avoid peak hours. Two migrations: stop reading (deploy first), drop (deploy after).
- **SDK breaking changes** require a major version bump per semver. Don't quietly remove from a minor.

## Rationalizations (and rebuttals)

| You'll be tempted to think…                                | Why it's wrong                                                                       |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| "Nobody's using this; just delete"                         | Run `cross-repo-impact` first. "Nobody" is an assumption that fails 30% of the time. |
| "I'll mark it deprecated and delete in the same PR"        | Then the marker is meaningless — consumers never get a window to react.              |
| "DB column is safe to drop in one migration"               | Reads in flight will fail. Stop reading first (deploy), then drop.                   |
| "I'll renumber the spec-registry ID after I delete the entry" | IDs are permanent. Retire, don't delete.                                          |
| "External SDK users will figure it out"                    | They won't. Announce, then wait, then remove.                                        |

## Red flags

- You haven't run `cross-repo-impact` and you're already writing the delete PR. Stop, run it.
- A consumer your agent missed is hitting the deprecated path in your shared dev environment (`environments.dev.name`). Revert the delete; fix the consumer.
- The deprecation PR and the delete PR are the same PR. Split.
- The spec-registry entry is being deleted instead of retired. Revert; IDs are permanent.
- You're dropping a DB column before stopping reads. Two migrations, not one.

## Verification

Done when:

- [ ] `cross-repo-impact` punch list is exhausted (every consumer migrated)
- [ ] Deprecation PR landed and was visible for the announced period
- [ ] Final delete PR landed; no error spike in the shared dev environment in the hour after
- [ ] If DB column: column is confirmed gone; no NULL-pointer or "column does not exist" errors in service logs
- [ ] If your org tracks capabilities: entry is `status: retired` with `retired_reason`; not deleted
- [ ] CHANGELOG updated; SDK version bump if semver-breaking

## Anti-patterns

- Single PR that deprecates AND deletes
- Deleting without `cross-repo-impact`
- DROP COLUMN without first stopping reads
- Deleting a spec-registry entry instead of retiring it
- Renumbering spec-registry IDs after retirement
- Quiet removals from SDK without a major version bump
