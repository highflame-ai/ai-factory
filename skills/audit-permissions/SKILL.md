---
name: audit-permissions
description: Review and clean up the standing Claude Code permission grants that accumulate in .claude/settings.json and settings.local.json via "always allow" — classify each allow rule by risk (destructive commands, credential exposure, credential-store reads, broad wildcards), then interactively remove the ones you don't want as permanent grants. Use periodically, or when `aif doctor`'s permissions-audit check fails. Auditing is safe-by-default; every removal is confirmed.
argument-hint: "[project dir] (defaults to current directory)"
---

# Audit-permissions — clean up standing permission grants

## Ethos

!`sh .aif/partials/ethos-include.sh 2>/dev/null || sh ~/.claude/skills/partials/ethos-include.sh`

## Input

Target: $ARGUMENTS

## Overview

Claude Code's "always allow" writes permission rules into `.claude/settings.json`
and `.claude/settings.local.json`. Over time the allow-list accumulates grants
nobody revisits — a one-off `Bash(curl … $TOKEN)`, a broad `Bash(*)`, a
`Bash(cat ~/.aws/credentials)` — each a permanent capability. This skill
surfaces the risky ones and removes only what you confirm. It **audits and edits
the allow-list; it never touches `deny`** (tightening is always safe) and never
removes a rule without your yes.

## When to use

- `aif doctor` reported a `permissions-audit` FAIL
- Periodic hygiene, or before sharing/committing a repo's `.claude/settings.json`
- After a burst of "always allow" clicks during heavy agent use

## Process

### Step 1 — Classify (shared classifier, one source of truth)

Run the classifier over this project's settings — the same one `aif doctor` uses, so the skill and the check never disagree:

```sh
# tools/ is the SIBLING of the skills symlink target (same pattern as forge.sh);
# resolve the script first — its exit code is the verdict, never a fallback trigger.
pa="$HOME/.claude/skills/../tools/aif/perm_audit.py"
[ -f "$pa" ] || pa="tools/aif/perm_audit.py"
python3 "$pa" --json
```

It reports each risky allow rule with a class and a reason:

- **remove** — a real risk as a *standing* grant: destructive commands (`rm -rf`, `DROP TABLE`, force-push), inline credentials, secret-env references, credential-store reads (`~/.ssh`, `~/.aws`, `.env`).
- **review** — overly broad wildcards (`Bash(*)`), `.env` file access (read-vs-setup is ambiguous by pattern), and settings files the auditor could not parse.
- **exempt** — a previously-kept grant recorded in `permissions-audit-exemptions.json`; shown for awareness, never fails.

If it reports nothing, say so and stop — the allow-list is clean.

### Step 2 — Present each finding for a decision

For each finding, show the rule, its file, its class, and *why* it's flagged, then get one decision:

- **remove** — delete the rule from that file's `permissions.allow`.
- **narrow** — replace a broad rule with a bounded one (e.g. `Bash(*)` → `Bash(npm run:*)`); ask the user for the replacement, don't guess it.
- **keep** — the grant is intentional. Record it in `.claude/permissions-audit-exemptions.json` as `{"exempt": {"<exact rule>": "<reason>"}}` — the classifier then reports it as `exempt` (informational) and `aif doctor` stays green. This file is the durable home for deliberate keeps; without an entry, the next audit re-flags the rule by design.

Default to the safe action (remove/narrow) but never apply without the explicit yes — a legitimate grant removed breaks the user's flow, so confirm each (ethos #7: the finding is a hypothesis until the human agrees).

### Step 3 — Baseline drift (ai-factory-specific, human-judged)

Beyond raw risk, compare the allow-list against the role-derived baseline the toolkit compiles (`compiled/claude/settings-*.json`). An allow rule that grants write/network beyond every role envelope is possible drift worth a look. This is **advisory and human-judged** — legitimate project rules (`Bash(make build:*)`) won't be in a role baseline and are fine; only surface entries that look like escalations, and let the user decide. Never auto-remove on baseline mismatch.

### Step 4 — Apply and re-verify

Apply confirmed edits by rewriting the affected `permissions.allow` array (preserve the rest of the file — key order, `deny`, `ask`, `hooks`, everything else untouched; edit only the allow entries the user approved). Then re-run Step 1 to confirm the `remove`-class findings are gone:

```sh
pa="$HOME/.claude/skills/../tools/aif/perm_audit.py"
[ -f "$pa" ] || pa="tools/aif/perm_audit.py"
python3 "$pa"; echo "exit=$?"
```

Exit 0 means no `remove`-class grants remain — the same green `aif doctor`'s `permissions-audit` check will now report.

## Failure modes to avoid

1. **Removing without confirmation** — a legit grant deleted breaks the user's flow; confirm every removal.
2. **Editing `deny` or `ask`** — this skill only prunes `allow`; don't loosen the deny list.
3. **Guessing a narrowed replacement** — ask the user what the bounded rule should be.
4. **Rewriting the whole settings file** — touch only the approved allow entries; leave key order and every other block intact.
5. **A keep without an exemption entry** — an unrecorded keep leaves `aif doctor` permanently red; write the `permissions-audit-exemptions.json` entry (with the reason) as part of the keep decision.
