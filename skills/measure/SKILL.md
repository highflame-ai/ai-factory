---
name: measure
description: Measure whether the toolkit is actually paying off — compute delivery and quality metrics from git history, merged PRs, and .aif/ artifacts (PR cycle time, rework/revert rate, spec-to-merge time, review-finding trends, skill/telemetry usage), report them with honest caveats about attribution, and save a dated baseline to compare over time. Use to establish a baseline at adoption and to check impact periodically. Applies our own ethos to ourselves: verify, don't trust.
argument-hint: "[--since <date-or-ref>] [--baseline]"
---

# Measure — is the toolkit paying off?

## Ethos

!`sh .aif/partials/ethos-include.sh 2>/dev/null || sh ~/.claude/skills/partials/ethos-include.sh`

## Input

$ARGUMENTS

## Overview

We built an elaborate apparatus; ethos #5 says verify, don't trust — so measure whether it works instead of assuming it. This skill computes delivery and quality signals from data that already exists (git, the forge, `.aif/` artifacts, telemetry) and reports them honestly: what the numbers are, what they do and don't prove, and where the toolkit plausibly moved them. It is **read-only and non-attributing** — it never claims the toolkit *caused* a change it can only correlate with.

## When to use

- **At adoption** (`--baseline`): capture where things stand BEFORE the toolkit is in real use, so later runs have a comparison.
- **Periodically** (monthly/quarterly): recompute and compare to the baseline.
- When someone asks "is this worth it?" — answer with data, not faith.

**Skip** for: repos with too little history to be meaningful (say so rather than reporting noise as signal).

## Process

### Step 1 — Set the window

`--since` sets the analysis window (a date or git ref; default: last 90 days). For a comparison run, also identify the prior baseline in `.aif/knowledge/metrics/` (if any).

### Step 2 — Delivery metrics (from git + forge)

Compute over the window; state the denominator for each so a small sample isn't dressed up as a trend:

```bash
SINCE="${SINCE:-90 days ago}"
SINCE_DATE=$(date -v-90d +%Y-%m-%d 2>/dev/null || date -d "$SINCE" +%Y-%m-%d)  # honor --since here too
# throughput
git log --since="$SINCE" --merges --oneline | wc -l          # merged PRs (merge-commit repos)
# cycle time (per merged PR): open -> merge. The flags below are GitHub-shaped
# passthrough; on Azure DevOps adapt them (az repos pr list --status completed)
# or skip cycle time with a note — do NOT silence errors and report empty data.
. .aif/partials/forge.sh 2>/dev/null || . ~/.claude/skills/partials/forge.sh
aif_forge_pr_list --state merged --search "merged:>$SINCE_DATE" --json number,createdAt,mergedAt | head
# rework signal: reverts and fix-of-recent-fix
git log --since="$SINCE" --oneline | grep -ciE '\brevert\b'
```

Report: **PR throughput**, **median cycle time** (open→merge), **rework rate** (reverts + hotfixes ÷ merges). Cycle time and rework are the two that most directly reflect whether spec-first + review is helping.

### Step 3 — Quality & process metrics (from .aif/ + telemetry)

- **Spec-to-merge**: for REQs in `.aif/specs/`, time from spec creation to the implementing PR's merge (where derivable).
- **Review-finding trend**: if `/review` reports are retained, count findings per review over time and how many were Critical/Important — falling severe-finding rate on stable diff sizes is a real signal; rising is too.
- **Knowledge growth**: lessons in `.aif/knowledge/lessons/` and entries in the known-warts registry over the window — is the codebase getting smarter (ethos #8)?
- **Skill/telemetry usage**: if `emit-step-telemetry` logs exist, which skills actually ran, and delegation ghost-skip counts from `check-delegation.sh`. Unused skills are a finding — either a gap or dead weight.

### Step 4 — Report honestly

Emit a dated report. For every metric: the number, its denominator/window, the trend vs baseline (if any), and a one-line **honest reading** that separates correlation from causation. Lead with a bluntly-labeled caveats section: confounders (team size, release cadence, sample size), what is NOT measured (actual defect-escape rate, developer experience), and any metric too noisy to trust this window. A metric you can't compute is reported as "not measurable here (reason)" — never silently dropped (ethos #5).

### Step 5 — Persist the baseline

Write the report to `.aif/knowledge/metrics/<YYYY-MM-DD>.md` (create the dir if absent). On a `--baseline` run, mark it as the baseline. This is the comparison point every future run reads — the measurement only becomes valuable over time.

## Failure modes to avoid

1. **Causation claims** — the toolkit correlates with, it does not provably cause. Say "improved alongside," not "the toolkit improved."
2. **Vanity metrics** — lines of code, commit count, raw skill invocations mean nothing about value; prefer cycle time, rework, escaped defects.
3. **Hiding the denominator** — "cycle time down 20%" over 5 PRs is noise; always show n.
4. **Silent drops** — an uncomputable metric is a reported gap, not an omission.
5. **Measuring too early** — with < ~20 merges in the window, report the numbers as indicative-only and say so.
