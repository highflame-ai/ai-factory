---
name: add-detector
description: Scaffolds a new detection/analysis module in your platform's extensible service — module code, registry registration, config wiring, telemetry signal contract, and verification at every tier. Use when adding a new detection or analysis capability to a plugin-style service.
---

# Add a new detection/analysis module

> **This skill is a TEMPLATE.** It encodes the generic workflow for extending a plugin-style service; the placeholders (`<your-detection-service>`, signal prefixes, tier names) are meant to be replaced. After `/init`, specialize this skill for your org: document your service's actual extension pattern in `.aif/context/` (e.g. `.aif/context/detector-pattern.md`) and rewrite the placeholder sections below to point at real files, interfaces, and conventions. The workflow shape — find a precedent → learn the contract → implement → register → emit telemetry → test at each tier — survives specialization unchanged.

## Overview

Adds a new detection/analysis module to `<your-detection-service>`, registers it in the service's module registry, wires its config, and confirms its signals flow through your observability pipeline — without breaking the service's dynamic signal-extraction contract (if it has one).

## When to use

- Adding a new detection/analysis capability to an extensible service (a new content check, a new classification signal, a new external-API-backed analyzer, etc.)
- The module emits signals that should land in your observability store and surface in your platform's signal UI

**Don't use** for:

- One-off tweaks to an existing module with no new signal keys
- New non-detection CRUD/admin concepts → use `/new-admin-module`

If this introduces a new platform-level promise ("we now detect X"), run `/feature-prep` FIRST — if your org keeps a spec registry (config key `org.spec_registry`), it may need a spec-only PR before the module code lands. If `org.spec_registry` is absent, skip the registry gate and say so.

## Before starting, confirm

Ask the user. Do not proceed without all six.

1. **Module name**: match the service's convention (typically snake_case), e.g. `phishing`, `pattern_repetition`
2. **What does it detect?** One sentence
3. **Tier / category** — extensible services usually bucket modules by execution profile, and the bucket picks the directory and config section. Typical tiers (replace with your service's actual ones, documented in `.aif/context/`):
   - `builtin` (sync, local CPU only — keyword/regex/static analysis)
   - `ml` (calls an internal model service)
   - `cloud` (calls an external third-party API)
   - `webhook` (customer-registered HTTPS endpoint)
4. **Signal outputs** — what the module emits, classified per the service's signal contract (commonly: boolean **flags**, numeric **scores**, string **labels**)
5. **Target taxonomy category**, if the platform maintains a threat/finding taxonomy. If it doesn't, skip and say so.
6. **Does it need scoped/hot-reloadable config?** (e.g. per-tenant keyword lists). If yes, the module must implement the service's config-reload interface; otherwise a plain config struct.

## The signal contract (MUST follow)

Most mature pipelines extract module signals **dynamically by naming convention** — a single extraction function classifies emitted values by type and key pattern, so new modules need zero changes to telemetry code, storage schema, or frontend. Find that function once (in `<your-detection-service>`'s telemetry layer) and record its rules in `.aif/context/`.

A typical contract looks like this — **replace with your service's actual one**:

| Signal type         | Value type                     | Key convention                              | Telemetry attribute        |
| ------------------- | ------------------------------ | ------------------------------------------- | -------------------------- |
| Flag                | `bool` (often only `true` is emitted) | descriptive name                     | `<prefix>.flag.<key>`      |
| Score               | numeric                        | a required suffix, e.g. `_score`/`_confidence`/`_ratio` | `<prefix>.score.<key>` (often normalized) |
| Label               | non-empty string (sentinels like `"none"`/`"unknown"` dropped) | descriptive name | `<prefix>.meta.<key>`      |
| Complex (array/map) | any                            | raw attributes only, no dedicated column    | (raw JSON)                 |

Follow the conventions and no storage / backend / frontend changes are needed. Break them and signals silently disappear — the pipeline drops what it can't classify.

## Process

### 1. Find the precedent module

Every extensible service has a canonical example per tier. Find the module closest to yours (same tier, similar signal shape) and read it end to end, including its tests. If `.aif/context/` names the canonical examples, start there; otherwise locate them yourself (list the module directory, pick the most-referenced or best-tested sibling) and record what you found.

### 2. Understand the interface contract

Read the module interface the service defines (e.g. an `interface.go` / abstract base class in the module package). Typical members: name/version, tier, the detect/analyze entrypoint, a declaration of the signal keys the module promises to emit, and a health check. Also identify:

- How results carry signals (usually a key→value map on the result object)
- Whether a config-reload interface exists for scoped/hot-reloadable config

Do not invent methods — copy the shape from the precedent module.

### 3. Implement the module

Create the module file in the directory your tier dictates, alongside its siblings in `<your-detection-service>`. Emit signals through the result's signal map following the contract from the table above, e.g. (illustrative):

```
"phishing_detected":   true          → flag
"phishing_score":      85            → score (suffix-bound)
"phishing_type":       "credential"  → label
"phishing_urls":       [...]         → raw attributes only (complex)
```

Declare the signal contract (the keys you promise to emit, with types) wherever the interface requires it.

### 4. Add the config struct to central config

Most services keep all module config in one central config file with per-tier sections. Add your module's config struct/section there, matching the convention of the tier you picked. Do not create a per-module config file unless the service's pattern uses them.

### 5. Register the module

Find where modules of your tier are registered at startup (a per-tier registration function in the service's main/startup path is common). Add the explicit registration call for your module with its config.

Check whether the service auto-discovers modules — most don't. If registration is explicit, forgetting this step means the module compiles but never runs.

### 6. Add the environment config entry

- Local/dev: the config the local stack consumes. If `local_stack.dir` is set in `.aif/config.yml`, the service's dev config lives under that directory; otherwise ask the user where dev config lives.
- Production: your org's deployed app config for `<your-detection-service>`.

Shape per tier — match what's already in the file (enabled flag, endpoints, timeouts, circuit-breaker settings, whatever your tier's siblings declare).

### 7. Verify telemetry emission

Sanity-check the signal-extraction function you found in step 2. Confirm your keys classify the way you intend (flag vs. score vs. label vs. raw).

**No edits should be needed.** If you find yourself wanting to edit the extraction function, your signal naming is wrong — rename your keys instead.

### 8. Confirm the downstream store handles new signals

If your pipeline materializes signals into a store (a materialized view, an ingestion transform, an ETL job), confirm it routes by the same prefix/type conventions — not a hardcoded key list.

**No migration should be needed.** If the transform uses a hardcoded key list, that's a bug in the transform — every future module would break the same way. Flag it rather than adding your key to the list.

### 9. Unit-test the module

Sibling test file, following the precedent module's test style (table-driven tests with positive/negative cases are typical):

- An input designed to trigger detection → expected flag/score/label
- A benign input → no signal

Run the service's test suite (e.g. `make test` in `<your-detection-service>`).

### 10. Local integration test

Bring up the local stack. If `.aif/config.yml` has a `local_stack:` section, use it:

```sh
cd <local_stack.dir>
<local_stack.up_command>
```

If `local_stack:` is absent, ask the user how to run the service locally, or fall back to the service's own README/Makefile.

Then exercise the service with input designed to trigger the module, and query the observability store directly to confirm your new signal keys landed in the right buckets (flags/scores/labels or your pipeline's equivalents).

### 11. Verify the display layer

If your platform has a signal UI, open it against the local stack and confirm the new signals render (flags as indicators, scores as bars/values, labels as rows — whatever the UI's generic rendering does).

**No frontend changes should be needed** if the UI renders signals generically. If it doesn't render, diagnose your signal naming first — don't add module-specific frontend code.

### 12. Verify in the shared dev environment after deploy

After merge and deploy to your shared dev environment (`environments.dev.name` in `.aif/config.yml`):

- If an MCP server is configured (`mcp.namespace` set), use its `mcp__<namespace>__*` tools to confirm the module is registered, fire it with synthetic positive input, and check for error-rate or latency regressions.
- If no MCP server is configured, say so and use local alternatives: the ordered `environments.dev.observability` sequence from config, `kubectl` if available, or direct queries — never fabricate live state.
- If `environments.dev` is absent entirely, skip this step and tell the user shared-environment verification wasn't configured.

### 13. Add to the taxonomy if needed

If this surfaces a new category and your platform maintains a taxonomy (a taxonomy repo or package):

- Update the taxonomy source
- Rebuild/republish it per its own conventions
- Bump the version if other repos pin it

Skip and say so if there's no taxonomy.

### 14. Documentation + commit

- Update `<your-detection-service>`'s CLAUDE.md if introducing a new pattern
- Update your architecture docs (`org.adr_dir` neighborhood, or wherever service docs live) with the module's purpose
- Single PR: module file + config struct + registration + environment config + taxonomy + tests + docs
- Subject: `feat: add <module> detector` — must match `org.commit_prefix_regex` (see `~/.claude/aif-references/commit-prefix-check.md`; conventional commits if the key is absent)
- After push, the `pr-shepherd` agent handles mechanical CI failures

## Rationalizations (and rebuttals)

| You'll be tempted to think…                                                | Why it's wrong                                                                                                          |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| "I'll skip the naming convention; the key reads better without the suffix" | Then the value lands in raw attributes only, not the classified bucket. The UI won't render it. Follow the convention.  |
| "I'll add a hardcoded key to the ingestion transform"                      | The transform is intentionally convention-based. Hardcoding a key means every future module breaks the same way.        |
| "I'll emit this count as-is and add a special case downstream"             | The contract is convention-driven on purpose. Rename the key to fit the contract instead.                               |
| "I'll add frontend rendering manually for this one module"                 | Defeats the dynamic-extraction contract. The frontend is generic; if it doesn't render, your naming is wrong.            |
| "An empty/sentinel label is fine, it just shows blank"                     | Pipelines typically drop empty strings and sentinels. Decide: emit a real value, or don't emit the key.                  |
| "I'll skip explicit registration; surely the registry auto-discovers"      | Verify before assuming. If registration is explicit, the registration call is the only way the module runs.             |

## Red flags

- You're editing the signal-extraction function in the service's telemetry layer. Your naming is wrong; rename instead.
- You're adding a hardcoded key to the ingestion transform. It should be convention-based; do not hardcode.
- The UI doesn't show your signal. Diagnose in this order: signal naming (convention/type), then startup registration, then the emitted telemetry attribute, then the store's column/bucket types.
- You skipped `/feature-prep` because "it's just one module." If this is a new platform promise and your org keeps a spec registry, the spec needs an entry first.
- You haven't verified with synthetic positive input after deploy. Always sanity-check in the shared dev environment (or say why you couldn't).

## Verification

Done when:

- [ ] The service's test suite passes with new module tests (sibling test file)
- [ ] The startup path registers the new module in the right per-tier function
- [ ] The central config has the module's config struct/section
- [ ] The dev environment config has the module's entry
- [ ] No edits to the signal-extraction function or the ingestion transform
- [ ] Local integration: the observability store shows the new signal keys in the right buckets
- [ ] The signal UI (if any) displays the new signals with zero frontend changes
- [ ] After deploy: the module shows as registered in the shared dev environment (via `mcp__<namespace>__*` tools, or stated local alternatives)
- [ ] Synthetic positive input fires the module in the shared dev environment
- [ ] No error-rate or latency regression in the hour after deploy

## Common pitfalls

- **Score key doesn't follow the required naming convention** → emitted but never classified as a score. Rename.
- **Label value is a sentinel** (`"none"`/`"unknown"`/`"N/A"`) → dropped. Emit a real value or skip the key.
- **Complex type emitted as a signal** → no dedicated column; lands in raw attributes only. Stick to bool/numeric/string for classified signals.
- **Forgot the registration call** → compiles, never runs.
- **Forgot the config struct/section** → config unmarshal silently leaves zero values; module starts with empty config.
- **Not running `/feature-prep` first** → mid-implementation discovery that the spec registry needed an entry. Cheaper upfront.
