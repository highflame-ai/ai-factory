---
name: rotate-secrets
description: Proactive secret rotation with an expiry gate — walk the org's secret inventory (secrets: in .aif/config.yml), find what's expiring or over max age, and drive each rotation through the overlap pattern (issue new → deploy alongside → verify → flip → revoke old) with a human approval gate before anything is revoked. Never prints a secret value. Use for "what's expiring?", scheduled rotation hygiene, or rotating a specific credential.
argument-hint: "[check | <secret-name>] [--days <threshold>]"
---

# Rotate-secrets — expiry gate + overlap-pattern rotation

## Ethos

!`sh .aif/partials/ethos-include.sh 2>/dev/null || sh ~/.claude/skills/partials/ethos-include.sh`

## Input

$ARGUMENTS

## Overview

Secrets fail on a schedule nobody is watching: the cert expires on a weekend, the API key outlives the employee, the signing key never rotates because rotating it is scary. This skill makes rotation boring — an inventory with expiry checks, and a fixed choreography per rotation where the **old credential is never revoked until the new one is proven live**. It operates the *process*; the sensitive material itself stays inside the secret store's own tooling.

## Hard safety rules (non-negotiable)

1. **Never print, log, or write a secret value** — not in output, not in the report, not in a temp file. Refer to secrets by name/store-path only. (The `secret-scan` hook blocks the obvious violations; the rule covers the rest.)
2. **Never revoke before verify.** The overlap pattern is the whole skill.
3. **Human approval gate before every revocation** — named secret, evidence the new credential is serving, then an explicit yes.
4. One secret at a time. A batch rotation that half-fails is an outage.

## When to use

- "What's expiring?" / scheduled expiry check (see `~/.claude/aif-references/trigger-recipes.md`)
- Rotating a specific credential (compromise suspicion, offboarding, policy age-out)
- Building the org's secret inventory for the first time

**Skip** for: revoking a credential that is actively being abused RIGHT NOW — that's incident response: revoke first via your provider's kill switch, accept the outage, then use this skill for the orderly replacement.

## Process

### Step 0 — Load the inventory

Read the `secrets:` section of `.aif/config.yml`:

```yaml
secrets:
  inventory:
    - name: <human-name>                 # e.g. payments-api-key
      kind: api-key | tls-cert | signing-key | db-credential | webhook-secret
      store: <where it lives>            # e.g. aws-secretsmanager:/prod/payments, k8s:ns/name
      consumers: [<service-or-repo>, …]  # who breaks if this rotates badly
      expiry_check: <command>            # optional: prints expiry date or days-left; MUST NOT print the value
      rotate_runbook: <path-or-note>     # optional: org-specific steps
      max_age_days: 90                   # optional: age-out policy when nothing expires naturally
```

**When absent**: switch to inventory-building mode — scan the repo(s) for secret *references* (env var names in manifests/compose files, secret-store paths in deploy configs, cert paths — names and paths only, never values), draft the `secrets:` section from what you find, ask the user to fill the gaps (`store`, `consumers`), and stop there. An inventory drafted today makes every future run real.

### Step 1 — Expiry gate (`check`, the default)

For each inventory entry, determine time-to-expiry: run its `expiry_check` when defined; otherwise use the kind's native probe where one exists (e.g. TLS: `openssl s_client`/`openssl x509 -enddate` against the cert; cloud keys: the provider CLI's metadata — created-date vs `max_age_days`). If neither works, mark it **unknown** — an unknown expiry is a finding, not a skip (ethos #5).

Report every entry (threshold: `--days`, default 30):

```
| secret | kind | expires / age | status: OK / EXPIRING / OVERDUE / UNKNOWN | consumers |
```

In `check` mode, stop here — the report is the deliverable.

### Step 2 — Plan one rotation

For the named secret (or the most urgent EXPIRING/OVERDUE one, with the user's confirmation), write the plan before touching anything: how the new credential is issued (per `rotate_runbook` or the store's standard mechanism), how both credentials can be valid simultaneously (dual API keys, cert bundle, dual JWKS entries — if the system genuinely cannot hold two, plan the maintenance window explicitly and say so), how each consumer picks up the new one, and what observation proves the new credential is serving (a log line, a metric, a successful authenticated probe — by name, never by value).

### Step 3 — Execute the overlap

1. **Issue** the new credential via the store's tooling (values flow store→consumer, never through this session's output).
2. **Deploy alongside** — add, don't replace, wherever the system supports dual credentials.
3. **Verify** — prove real traffic authenticates with the NEW credential (watch the consumers from `consumers:`; a probe that only proves the old one still works proves nothing).
4. **HUMAN GATE** — present the evidence; get an explicit yes for revocation.
5. **Revoke** the old credential; watch consumers for fallout for the agreed window.
6. **Record** — update the inventory entry (rotation date), append the rotation to wherever the org logs them (dates, names, evidence — no values).

### Step 4 — Verify the end state

Old credential no longer authenticates (a probe with it should now FAIL — that failing is the success condition); all consumers healthy; inventory updated.

## Failure modes to avoid

1. Echoing a secret value "just to check it" — never; verify by behavior, not by inspection.
2. Revoke-then-verify — the order is the outage.
3. Rotating everything expiring in one heroic session — one at a time.
4. Treating UNKNOWN expiry as OK — it's the riskiest row in the table.
5. Skipping the inventory update — the next run (or the next engineer) inherits your rotation as a mystery.
