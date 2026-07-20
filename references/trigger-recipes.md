# Trigger recipes — running skills autonomously

The toolkit's skills are session-invoked by design: a human (or another skill) starts them, and hooks provide the deterministic gates. But most skills also run well **unattended** — on a schedule, on a PR event, or after a merge — using Claude Code's own primitives. This reference is the recipe book. Nothing here is wired by default; each recipe is opt-in per repo or per CI system.

## The three trigger primitives

| Primitive | What it is | Fits |
|---|---|---|
| **Headless mode** — `claude -p "<prompt>"` | One non-interactive Claude Code run; exits when done. Runs anywhere a shell runs: CI jobs, cron, git server hooks. | CI gates, post-merge jobs, scheduled audits |
| **Hooks** — `.claude/settings.json` | Deterministic shell commands on session events (SessionStart, PreToolUse, PostToolUse, Stop). Already used by this toolkit's formatters and gates. | Per-edit/per-commit enforcement — not for launching long skill runs |
| **Scheduled agents** | Claude Code's scheduled/cloud runs (see `/schedule` in a session, where available). | Recurring jobs without your own cron infrastructure |

Two rules apply everywhere:

1. **Unattended runs get the least privilege that works.** Use the role overlays the compiler emits — `claude --settings compiled/claude/settings-<role>.json` (reviewer for review sweeps, scanner for audits, orchestrator only where the job must push) — never `--dangerously-skip-permissions` on a repo with push access. Throwaway branch or read-only checkout where the recipe allows it.
2. **Unattended output is a draft.** Every recipe below ends in a PR, a report file, or a posted comment — a human merges/acts. That's ethos #5: the run produces evidence, not silent mutations.

## Recipes

### Nightly codebase health audit

```bash
# cron / scheduled CI job, from the repo root
claude -p "/analyze" --output-format text > analyze-report-$(date +%Y%m%d).txt
```

Post the report wherever the team reads (CI artifact, Slack via your CI's notifier). Pair with `/optimize` weekly.

### Review sweep on every PR (CI job)

```bash
# in the PR's CI pipeline, after checkout of the PR branch
claude -p "Run /review on the current branch's diff against origin/main. Post nothing; write findings to review-findings.md" 
```

Upload `review-findings.md` as a CI artifact or post it as a PR comment with `gh pr comment`. For a harder gate, fail the job when the file contains a `[CRITICAL]` finding.

### Doc drift check after every merge

```bash
# post-merge CI job on the default branch
claude -p "/doc-drift HEAD~1..HEAD" 
```

`/doc-drift` opens its own PR (via the forge adapter) when it finds stale docs, so the job needs push + PR permissions — scope its token accordingly.

### Weekly vetted dependency updates

```bash
# weekly cron
claude -p "/dep-update scan --security-only"
```

Security-only keeps the unattended batch small and mergeable. Run the full (non-security) pass interactively where a human can approve major bumps.

### Release notes on tag

```bash
# CI job triggered on tag push
claude -p "/release-notes ${TAG} --audience all"
```

The draft lands in the job's workspace; attach it to the GitHub release as a draft body — a human edits and publishes.

### License gate on lockfile changes

```bash
# CI job when the diff touches a lockfile (package-lock.json, pnpm-lock.yaml, go.sum, Cargo.lock, uv.lock)
claude -p "/license-audit --changed-since origin/main"
```

`/license-audit` exits non-zero only on **denied** components (per `org.license_policy`); needs-review findings report without failing the build. Run the full audit (no `--changed-since`) monthly.

### Weekly secret expiry check

```bash
# weekly cron — check only; rotation stays interactive
claude -p "/rotate-secrets check --days 30"
```

Post the expiry table to the team channel. Actual rotation runs interactively — the human approval gate before revocation is the point of the skill, so don't headless it.

### PR babysitting after push

`@pr-shepherd` is agent-shaped rather than skill-shaped: launch it from the session that opened the PR ("launch @pr-shepherd on <owner/repo>#<n>"), or headless from CI after the PR opens. It already gates its Slack ping on `org.slack.pr_channel`.

### Threat model on security-labeled specs

```bash
# CI job when a PR touches the spec registry or carries a `security` label
claude -p "/threat-model <path-to-spec-changed-in-this-pr>"
```

## What NOT to automate

- `/proceed`, `/sprint`, `/wrapup` — these are orchestrators with human gates built in; running them unattended defeats the gates the pipeline exists for. Use `/sprint`'s own engine for parallelism *inside* a supervised session instead.
- Anything that merges. No recipe here merges a PR; keep it that way.
- `/adversary` in a merge-blocking gate before you've calibrated its findings volume on your codebase — a noisy blocker trains people to override blockers (ethos #6, in reverse).
