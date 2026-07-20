---
name: license-audit
description: License and SBOM compliance audit — build a software bill of materials from the repo's actual dependency graph, resolve every component's license, judge each against the org's license policy (org.license_policy), and report allowed / denied / needs-review with evidence. Use on "are our licenses clean?", before a release or customer security review, or when a lockfile changes.
argument-hint: "[--sbom-only | --changed-since <ref>]"
---

# License-audit — SBOM + license policy compliance

## Ethos

!`sh .aif/partials/ethos-include.sh 2>/dev/null || sh ~/.claude/skills/partials/ethos-include.sh`

## Input

$ARGUMENTS

## Overview

License risk enters the codebase one lockfile line at a time and is invisible until a customer audit or an acquisition finds it. This skill makes it visible on demand: a real SBOM from the dependency graph (transitive included, where tooling allows), each component's license resolved from evidence, and a verdict per component against the org's policy. The output is a report and an artifact — the merge/remediation decision stays human.

## When to use

- "Are our licenses clean?" / preparing for a customer security review or due diligence
- A lockfile changed and you want a compliance check before merge (see `~/.claude/aif-references/trigger-recipes.md`)
- Producing an SBOM artifact for a release (`--sbom-only`)

**Skip** for: dependency *upgrades* (that's `/dep-update` — though run this after a big batch), and legal interpretation of a specific license's obligations — flag those for counsel, don't improvise legal advice.

## Process

### Step 1 — Resolve the policy

Read `org.license_policy` from `.aif/config.yml`:

```yaml
org:
  license_policy:
    allow: [MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC]
    deny:  [AGPL-3.0-only, SSPL-1.0]
    # anything not listed either way -> needs-review
```

**When absent**: do NOT invent a policy. Run the inventory anyway, classify every component as `allowed-by-default` or `needs-review` (strong copyleft and unknown licenses go to needs-review), state clearly that no org policy is configured, and offer to write one into `.aif/config.yml` from the findings.

### Step 2 — Build the SBOM

Prefer a dedicated SBOM tool when present; fall back per toolchain; always say which path produced the data:

```bash
command -v syft >/dev/null && syft . -o spdx-json > sbom.spdx.json
# Fallbacks per manifest, transitive where the tool supports it:
[ -f go.mod ]       && go list -m -json all 2>/dev/null | head -5   # + go-licenses if installed
[ -f package.json ] && { (command -v pnpm >/dev/null && pnpm licenses list --json) || npx --no-install license-checker --json; } 2>/dev/null | head -5
[ -f pyproject.toml ] || [ -f requirements.txt ] && (command -v pip-licenses >/dev/null && pip-licenses --format=json) 2>/dev/null | head -5
[ -f Cargo.toml ]   && (command -v cargo-license >/dev/null && cargo license --json) 2>/dev/null | head -5
```

If a toolchain has no license tooling installed, list its dependencies anyway and resolve licenses in Step 3 — a partial SBOM labeled partial beats a silent gap (no silent caps). `--changed-since <ref>` narrows the audit to components added/updated since that ref (diff the lockfiles).

### Step 3 — Resolve licenses with evidence

For each component whose license the tooling reports as unknown, ambiguous (`SEE LICENSE IN …`), or dual (`MIT OR GPL-2.0`): read the actual license file in the dependency's source (module cache, `node_modules/<pkg>/LICENSE`, or the upstream repo via `gh`). Record WHERE each license claim came from — registry metadata vs license file read — because metadata lies often enough to matter (ethos #1). Dual-licensed components are judged by the license the org would actually elect, and that election is recorded.

### Step 4 — Judge and report

Classify every component: **allowed** / **denied** / **needs-review** (unknown, unlisted, ambiguous). Write the report:

```markdown
# License audit — <repo> — <date>
Policy: org.license_policy (or "none configured — advisory mode")
SBOM: <path> (<tool used>; transitive: yes/no per toolchain)

## Denied (N)           <- component, version, license, evidence source, where it entered (direct/transitive via X)
## Needs review (N)     <- same columns + why it's ambiguous
## Allowed (N)          <- one line per license family with component counts
## Coverage gaps        <- toolchains/components the audit could NOT resolve, and why
```

Every section appears even when empty (ethos #5). For denied components, list the realistic remediations: replace, isolate, or seek a commercial license — but do not pick one unilaterally.

### Step 5 — Persist

Save the SBOM + report where the org keeps compliance artifacts (ask on first run; suggest `.aif/knowledge/compliance/`). In CI mode (trigger recipe), exit non-zero when a **denied** component is found; needs-review findings never fail the build — they page a human.

## Failure modes to avoid

1. Trusting registry license metadata without reading the license file for anything non-obvious (ethos #1).
2. Inventing a policy when none is configured — advisory mode + offer to write one.
3. Failing CI on needs-review items — that trains people to override the gate (ethos #6, in reverse).
4. Giving legal interpretations ("GPL is fine here because…") — flag for counsel.
5. Auditing only direct dependencies and calling it complete — label transitive coverage per toolchain honestly.
