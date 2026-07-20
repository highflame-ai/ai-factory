---
name: org-skill-skeleton
description: Skeleton for an org-specific skill — copy into skills/, rename, and fill in. Encodes a recurring multi-step workflow your org performs (a deploy runbook, a release checklist, an onboarding scaffold).
argument-hint: "<what the skill needs from the user>"
---

# <Skill name> — <one-line purpose>

## Ethos

!`sh .aif/partials/ethos-include.sh 2>/dev/null || sh ~/.claude/skills/partials/ethos-include.sh`

## Context

!`cat .aif/context/conventions.md 2>/dev/null || echo "No conventions doc found"`

## Input

$ARGUMENTS

## When to use

- <trigger phrase or situation 1>
- <trigger phrase or situation 2>

**Skip** for: <when a lighter tool is right — a direct edit, a different skill>.

## Process

### Step 1 — <verb phrase>

<What to read or verify first. Prefer authoritative sources (config, code, MCP tools via `mcp.namespace`) over assumptions — state which source answers which question.>

```sh
# POSIX-only in sh fences. Read org values from config, never hardcode:
grep -A2 "^org:" .aif/config.yml 2>/dev/null || echo "org: section not configured"
```

### Step 2 — <verb phrase>

<The core work. If a `.aif/config.yml` key drives behavior, name the key and say what happens when it is absent.>

### Step 3 — Verify

<Every skill ends with evidence: the command to run and what output constitutes "done". "Looks right" is not done (ethos #5).>

## Failure modes to avoid

1. <the shortcut this skill exists to prevent>
2. <the second most common mistake>
