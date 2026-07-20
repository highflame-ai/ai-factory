---
name: source-driven
description: Replaces speculation with reading the source. Before writing code that depends on a contract, schema, deployed state, or platform invariant, query the authoritative source — MCP tools when configured, your org's spec registry and ADRs when they exist, otherwise the codebase itself — instead of recalling from memory. Use when implementing anything that touches an external contract you don't have the file open for.
---

# Source-driven implementation

## Overview

Most "Claude wrote code that doesn't match reality" bugs come from one root cause: **the model recalled a contract instead of reading it**. This skill is the discipline that fixes that. Before writing code that depends on a contract, query the authoritative source.

The authoritative sources are parameterized by `.aif/config.yml`:

- **Live platform state** (DB schema, deployed config, service state) → MCP tools `mcp__<namespace>__*`, with `<namespace>` from `mcp.namespace` (if configured)
- **Capability / invariant promises** → the spec registry at `org.spec_registry` (if configured)
- **Architecture decisions and contracts** → the ADR directory at `org.adr_dir` (if configured)
- **Everything else — types, interfaces, actual behavior** → the codebase itself, via `Read` and `Grep`

When a config key is absent, that source simply doesn't exist for your org — fall through to the codebase, or ask the user where the contract lives. **Never fabricate a substitute.**

## When to use

- About to call a service's API and you're not sure what it accepts
- Adding a query against a table whose columns you're guessing at
- Implementing logic that depends on what config is deployed in the shared environment
- Writing anything that needs to match a live, deployed schema
- Touching any cross-service contract you don't have open in front of you

**Skip** for: pure refactors of code you have open, bug fixes whose contract is already in the diff context, anything where the source is in the file you're editing.

## Process

### Step 1 — name the contract

Write down in one line: **what's the contract this code depends on?**

Examples:

- "billing-service's `/v1/invoices` request body shape"
- "the `orders` table's `status` column type"
- "the config key `CACHE_TTL` the worker reads at boot"
- "the span-attribute prefix our telemetry pipeline extracts"

If you can't name the contract, you don't yet know what to read. Stop and clarify.

### Step 2 — pick the source

| Contract type                             | Source                                          | Tool                                                       |
| ----------------------------------------- | ----------------------------------------------- | ---------------------------------------------------------- |
| Cross-service or platform contract        | ADRs / architecture docs (`org.adr_dir`)        | `Read`, or MCP docs tools if your server exposes them      |
| DB schema (columns, indexes, constraints) | live shared-environment DB                      | MCP describe-table tool (`mcp__<namespace>__*`)            |
| Deployed runtime config                   | orchestrator config in the shared environment   | MCP configmap/config tool, or `kubectl` if you have access |
| Live service state (rules, plugins)       | the service itself via MCP or HTTP              | the service's state/health tools                           |
| Code-level type or interface              | the repo itself                                 | `Read`, `Grep`                                             |
| Capability or invariant promise           | the spec registry (`org.spec_registry`)         | `Read`                                                     |
| Telemetry attribute conventions           | your org's observability doc (if one exists)    | `Read`                                                     |

If `mcp.namespace` is set, see `~/.claude/aif-references/mcp-tools-cheatsheet.md` for the full intent → tool map. If a row's source isn't configured for your org, use the codebase (the deployed code IS the contract) or ask the user — do not invent the source.

### Step 3 — read it

Actually read it. Don't search the file name and assume. The point of this skill is the moment your fingers hit the read tool instead of trusting recall.

If the source is large, read the relevant section. If you can't find the relevant section, read the index/TOC first and then drill in — don't paste the whole file into context.

### Step 4 — note the version / freshness

- ADRs / architecture docs: pinned to the version you have checked out
- DB schema via a live describe-table query: accurate as of now
- Deployed config: accurate as of now (note: a pod may not have restarted to pick up new config)
- Spec registry: pinned to `main` (or your branch); if you're proposing a `NEW_ENTRY`, the spec PR lands first

If the source is stale, fix the source before writing code against an outdated contract.

### Step 5 — implement, citing the source

When summarizing your implementation in chat, cite the source you consulted:

> Read the ADR on the detector pipeline to confirm the score-attribute prefix is extracted downstream. Implementing the new score key to match the convention.

The citation is for the user's benefit — they can verify your source matches their expectation.

## What this skill replaces

| Anti-pattern                                  | Replace with                                                                            |
| --------------------------------------------- | ---------------------------------------------------------------------------------------- |
| "The JWT claims include `org_id` I think"     | `Read ~/.claude/aif-references/jwt-checklist.md` for the actual claim names                     |
| "The `orders` table has a `status` column"    | describe the table via MCP, or read the migration files                                  |
| "The service emits `risk_score`"              | `Grep` the service's code, or hit its live state endpoint                                |
| "The config key is `MAX_CONCURRENCY`"         | read the deployed config, or the service's config-loading code                           |
| "Conventional Commits supports that prefix"   | `Read ~/.claude/aif-references/commit-prefix-check.md` and check `org.commit_prefix_regex`      |

## Source unavailable — no fallback fabrication

There is no fallback. If the source a contract needs is unreachable (MCP server down, registry not configured, doc missing), **surface the failure and stop** — say exactly which source you needed and why. Guessing "what it probably says" is precisely the bug this skill exists to prevent. If `mcp.namespace` is set, see `~/.claude/aif-references/mcp-tools-cheatsheet.md` § "When NOT to use MCP" for the full rationale.

## Rationalizations (and rebuttals)

| You'll be tempted to think…                                             | Why it's wrong                                                                                                                                     |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| "I just looked at this last week, I remember the schema"                | Memory drifts. Schemas drift faster. The 30-second describe-table query is cheaper than the 30-minute "why is my query returning 0 rows" debug.      |
| "The doc is too long to read; I'll skim the section title"              | Skimming is what produces "code that looks right." Read the relevant section.                                                                        |
| "I'll write the code first, then verify"                                | The verification almost never gets done. Read first, write second.                                                                                   |
| "MCP is just a wrapper around things I could grep"                      | Some yes (docs), most no (live DB, orchestrator state, service state). Use it when configured.                                                       |
| "If the source is wrong, the code will be wrong — fine, I'll fix later" | Wrong source = wrong code = wrong tests = wrong PR description. Fix the source first.                                                                |

## Red flags

- You're writing code with a TODO comment like "// confirm field name." That's the moment to query the source, not after.
- Your reasoning includes "the API probably accepts…" — replace "probably" with a read of the doc or a `Grep` of the implementation.
- You closed the doc file before finishing the implementation. Keep it referenced; cite it in the diff or PR.
- A live source disagrees with a static doc (e.g. `workspace-CLAUDE.md`). The live source wins; update the static doc separately.

## Verification

Done when:

- [ ] Every contract the code depends on has a named source you actually read
- [ ] The implementation cites at least one source in chat output
- [ ] No "probably" / "I think" reasoning in the implementation summary
- [ ] If a source was stale, it's fixed in this PR or a follow-up is filed

## Anti-patterns

- Writing code against remembered contracts
- Using `WebFetch` for docs that live locally (e.g. the directory `org.adr_dir` points at)
- Trusting a static summary doc over a live query (the static doc lags)
- Citing the source in chat but not actually reading it
- Skipping the cite — even a one-line "read X §Y" beats no provenance
- Inventing a fallback answer when the source is unreachable — surface the failure instead
