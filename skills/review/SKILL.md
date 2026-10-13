---
name: review
description: Multi-agent code review covering correctness, quality, architecture, test coverage, and security
argument-hint: Optional file paths, branch name, or REQ/TASK ID to scope the review
---

# /review — Multi-Agent Code Review

You are performing a thorough code review of recent changes using multiple specialized review agents.

This skill is the **pre-push AIF review gate**. It runs 5 specialized review agents in parallel, covering the same dimensions the CI `llm-review` workflow would cover if it ran (correctness, conventions, test coverage, security) plus an architecture dimension the CI workflow doesn't have. Running this before pushing means the AIF gate catches issues regardless of whether the CI layer is available — CI-layer LLM reviews can be blocked (billing, infra, outages) and must not become the sole safety net.

## Ethos

!`sh .aif/partials/ethos-include.sh 2>/dev/null || sh ~/.claude/skills/partials/ethos-include.sh`

## Context

- Current branch: !`git branch --show-current 2>/dev/null || echo "Not a git repo"`
- Recent changes: !`git diff main --stat 2>/dev/null || echo "No diff available"`

**Context files loaded on demand**: `.aif/context/conventions.md` and recent lessons are loaded by Step 1 below — **skip the Reads if they are already in the current conversation** (e.g., when invoked from `/proceed`, which preloads `conventions.md` at Phase 0).

## Input

Scope: $ARGUMENTS

## Prerequisites

Before proceeding, verify that `.aif/context/conventions.md` exists. If it doesn't, stop and tell the user: "The `.aif/` structure hasn't been initialized. Run `/init` first to set up conventions."

## Instructions

### Step 1: Determine Review Scope and Load Context
1. If given specific file paths, review those files
2. If given a branch name, review all changes on that branch vs `main`
3. If given a REQ/TASK ID, find the associated branch and review its changes
4. If no argument, review all uncommitted changes + commits on the current branch vs `main`
5. Get the full diff: `git diff main...HEAD` (or `git diff` for uncommitted changes)
6. **Conventions**: if `.aif/context/conventions.md` is NOT already in your conversation context, Read it now. Otherwise skip — it's already loaded.
7. **Relevant lessons** (mirrors the spirit of `llm-review.yml`, but relevance-ranked instead of time-ranked):
   a. Derive the set of touched **components** from the diff. Components are inferred from file paths — e.g. `api/auth/*` → `API/auth`, `app/Sources/Views/*.swift` → `iOS/SwiftUI`, `infrastructure/terraform/*` → `infra/terraform`. Produce a short list of plausible `component` values and a broader list of `domain` values (e.g. `API`, `iOS`, `infra`).
   b. Glob `.aif/knowledge/lessons/*.md` and read each file's frontmatter (`domain`, `component`, `tags`). Keep lessons where `component` matches any touched component exactly, OR where `domain` matches any touched domain AND `component` is a prefix of a touched component, OR where any tag matches a touched component/domain. This is the **relevance set**.
   c. If the relevance set has fewer than 5 entries, top it up with the most recently modified lessons from `.aif/knowledge/lessons/` (the previous time-based heuristic) until the set has up to 10 entries. This keeps small or cross-cutting diffs from losing context entirely.
   d. Cap the final list at 15 lessons. Read their bodies in full.
   e. Pass the content of every selected lesson as context to every review agent in Step 3. When a finding later matches one of these lessons, cite its `id` explicitly (Step 4 uses this to elevate severity).
   **Fallback**: if any lesson has no `component` / `domain` / `tags` frontmatter (legacy file), fall back to reading its title + first paragraph and include it only if the title contains any touched domain or component substring. Do not skip it silently — it may be load-bearing.

### Step 2: Read All Changed Files
Read the complete current version of every changed file (not just the diff) to understand full context.

### Step 2b: Triage — size the bench to the risk

Not every diff earns the full bench. Classify the change and pick the tier — the floor is always one real reviewer, never a rubber stamp:

| Tier | Criteria (ALL must hold for the lower tier) | Bench |
|---|---|---|
| **Light** | ≤2 files AND ≤50 changed lines AND no auth/authz, data access, migrations, config/env, tenant-scoping (`tenancy.keys`), public API, or concurrency surfaces | correctness-reviewer only |
| **Standard** | ≤10 files AND none of the sensitive surfaces above | correctness-reviewer + quality-reviewer + test-auditor |
| **Full** | anything larger, anything touching a sensitive surface, or any doubt | all 5 agents |

Sensitive surfaces always force **Full** regardless of size — the blast radius of "small but in auth code" is not small. State the chosen tier and the reason in the report header. If the user explicitly asked for a thorough review, use Full regardless.

### Step 2c: Spec adherence input (when a spec is linked)

A change's spec is wherever the org keeps it, not only an AIF REQ. Collect every source that resolves, from the argument, branch name, commit messages, and PR body:

| Source | How it is referenced | What to read |
|---|---|---|
| AIF REQ | `feat/REQ-…` branch, `REQ-<id>` in argument / PR body | that spec's `requirement.md` acceptance criteria |
| Spec registry entry | an entry ID that exists in the file at `org.spec_registry` in `.aif/config.yml` (e.g. a capability or invariant ID cited in a commit or the PR body) | the entry, plus the doc its own pointer field names (one hop) |
| Linked issue | `Closes #N` / `Fixes owner/repo#N` / issue URL in the PR body or commits | the issue body and its discussion (`gh issue view <n> --json title,body,comments` when `aif_forge_provider` is `github`; on other forges use that forge's CLI, or record the issue as unresolved) |
| ADR | an ADR path or number cited by any source above, resolved under `org.adr_dir` | its decision and consequences sections |

Follow references **one hop** (an issue that cites an ADR pulls in that ADR) and no further. Only read registry entries whose IDs actually appear in those references; never scan the whole registry for anything that looks related.

From what resolved, build one numbered acceptance-criteria list, each item tagged with its source, including the negative ones (what must be rejected, what must never happen, what is out of scope). Add to EVERY dispatched agent's inputs: that list, plus the instruction "flag (a) any acceptance criterion the diff does not satisfy, (b) any significant implemented behavior the spec never asked for — unrequested scope is a finding, not a bonus — and (c) any spec text the diff makes stale (doc follow-up, not a code defect)."

**Hand the agents the sources, not your reading of them.** The criteria list is a checklist you derive from the source text. Do not add the implementer's rationale, "this deviation is deliberate", or a summary of what was built. Review agents start with a fresh context, and that is most of their value. When `/review` runs as a pack phase it shares a session with the implementer (codeoid runs every phase as a turn on the run's bound session), so this hand-off is the only thing keeping the bench fresh. A deliberate deviation still comes back as a finding; whoever acts on the review resolves it by changing either the code or the spec, never by dropping it.

Record in the report header which sources resolved and which pointers did not. Skip silently only when there is no pointer at all.

### Step 2d: Activate domain experts (path-scoped context)

Experts are curated, path-scoped domain context (`.aif/experts/*.md`; authored via `/expert`). Unlike lessons (relevance-ranked from incidents) they activate by **path match**, so a change in a domain gets that domain's load-bearing context injected:

a. If `.aif/experts/` is absent or empty, skip silently — experts are optional.
b. Read each expert's frontmatter (`applies_to` globs). An expert **activates** when any of its globs matches any touched file in the diff.
c. Read the body of every activated expert in full and pass it to every dispatched agent in Step 3, labeled by domain. When an activated expert names a `signal:` (its verify command), hand that to the test-auditor as the domain's expected verification.
d. Note the activated experts in the report header (e.g. `experts: react-frontend, dynamodb-access`). No expert activated on a diff that clearly sits in a documented domain is itself a signal — mention it, so the gap gets an `/expert` later.

### Step 3: Launch Review Agents
Launch the tier's agents **in parallel** using the Agent tool (5 for Full — listed below; the subset per Step 2b otherwise). Each agent is defined in `~/.claude/agents/` with its full checklist, model selection, and tool restrictions. Running in parallel minimizes wall-clock time.

1. **correctness-reviewer** agent — provide it the list of changed files, the full diff, `conventions.md` content, and recent lessons. Focus: logic errors, null risks, race conditions, edge cases, concurrency bugs. Tell it: "Report findings only. Do not apply fixes."
2. **quality-reviewer** agent — same inputs. Focus: naming, convention compliance, code duplication, complexity, maintainability. Tell it: "Report findings only. Do not apply fixes."
3. **architecture-reviewer** agent — same inputs plus `architecture.md` content. Focus: layering, separation of concerns, API contracts, module boundaries, scope discipline. Tell it: "Report findings only. Do not apply fixes."
4. **test-auditor** agent — same inputs. Focus: test coverage gaps for the changed code, mock completeness, edge case coverage, test isolation, determinism. Tell it: "Audit test coverage only for the diff under review. Report findings only. Do not apply fixes."
5. **security-auditor** agent — same inputs. Focus: input validation, authentication/authorization gaps, data exposure (PII, secrets), injection risks, dependency issues, rate limiting. Tell it: "Audit security posture only for the diff under review. Report findings only. Do not apply fixes."

Each agent returns structured findings with severity (Critical/Major/Minor/Nit), file path, line number, and suggested fix.

**Gate rule** (mirrors `llm-review.yml`): if ANY agent reports a `Critical` finding, the review gate FAILS and the changes are not ready to merge. Fix critical findings before proceeding to push. Major findings should typically be fixed before merge but can be escalated to the user for judgment calls.

### Step 4: Consolidate Findings
1. Collect results from all 5 agents
2. Deduplicate overlapping findings
3. Categorize by severity:
   - **Critical**: Must fix before merge (bugs, security, data loss, test gaps that hide regressions)
   - **Major**: Should fix before merge (convention violations, missing tests, architectural smells)
   - **Minor**: Nice to fix (style, naming, minor improvements)
   - **Nit**: Optional suggestions
4. Spec findings (Step 2c) keep their source tag. A missed or contradicted criterion is Major at least, and Critical when the criterion is a security, tenancy, or "must never" invariant. Stale-spec items are listed separately as doc follow-ups, not as code defects.
5. Cross-reference findings against the loaded recent lessons — if a finding matches a known pitfall, escalate its severity by one level (e.g., a Minor finding that matches a prior LESSON becomes a Major). Flag this explicitly in the report.

### Step 5: Present Review
Display findings organized by file, then by severity within each file. Include a dimension summary at the top so the user can see which of the 5 dimensions have issues at a glance:

```
## Dimension Summary

| Dimension | Critical | Major | Minor | Nit | Gate |
|---|---|---|---|---|---|
| Correctness | 0 | 1 | 2 | 0 | PASS |
| Quality | 0 | 0 | 3 | 1 | PASS |
| Architecture | 0 | 2 | 0 | 0 | PASS |
| Test Coverage | 0 | 0 | 1 | 0 | PASS |
| Security | 0 | 0 | 0 | 0 | PASS |

**Overall gate: PASS / FAIL**

## file/path.js

### Critical
- Line XX: description of issue

### Major
- Line XX: description of issue
```

### Step 6: Summary
1. Overall gate: PASS (ready to merge) / FAIL (fix criticals first) / RESHAPE (significant rework needed)
2. Count of issues by severity and by dimension
3. Top 3 most important things to address
4. Any findings that matched recent lessons (elevated-severity items)
5. If changes look good, say so clearly — an empty review is a valid result for small, well-scoped changes
