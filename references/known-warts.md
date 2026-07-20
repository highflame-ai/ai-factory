# Known warts — load-bearing oddities of your platform

A **known-warts registry** is a curated, append-only list of the facts your code doesn't tell you and your docs haven't been updated for: known-broken CI gates that should be ignored, intentionally-skipped tests, no-op safeguards, and contracts that diverge from naming intuition. They're the kind of thing that lives in someone's head, surfaces during a frustrating debug session, and gets re-discovered next quarter.

**Why it prevents agent confusion:** a Claude session that hits a red CI gate will, absent this file, spend real time (or make real changes) trying to "fix" something the org has already decided to ignore — or worse, cite a no-op coverage gate as evidence that coverage passes. Writing each wart down once kills that cycle for both agents and humans.

**Updating this file:** when you discover a non-obvious wart that the next person will re-discover in 30 minutes, add a one-line entry under the right section with a date, the wart, and a one-line "why it matters / what to do." Don't expand a section into prose — if a wart needs prose, link out to a longer doc.

---

## Template — fill in for your org

The sections below are the recommended taxonomy. All tables start empty; delete sections that never accumulate entries.

### CI gates that are known-broken / known-noop

Gates agents should neither retrigger nor treat as evidence.

| Date       | Repo   | Gate   | Status | What to do |
| ---------- | ------ | ------ | ------ | ----------- |
|            |        |        |        |             |

Example entry shape: "`api` / lint gate / Known-broken — fails on a linter config issue unrelated to the diff; do not block PR merges on it; fix queued separately." Or: "shared coverage gate is a silent no-op for `worker` — treat coverage as unmeasured at the CI level; don't claim it passes."

### Tests excluded from canonical gates (intentional)

Deterministically-failing or quarantined-flaky tests that are excluded on purpose — so nobody chases them locally as if they were regressions.

| Date       | Repo   | Test(s) | Status | Why excluded / tracking |
| ---------- | ------ | ------- | ------ | ------------------------ |
|            |        |         |        |                          |

### Service & feature contracts that diverge from naming intuition

Places where a name lies: an enum that mixes two concepts, a flag whose default surprises, a service that doesn't need the dependency an audit claims it does.

| Date       | Where  | Wart | What to do |
| ---------- | ------ | ---- | ----------- |
|            |        |      |             |

### Regression suite gotchas

Fixture scoping traps, marker-name mismatches, in-flight test-topology migrations — anything that makes a red regression run mean something other than "your change broke it."

| Date       | Wart | What to do |
| ---------- | ---- | ----------- |
|            |      |             |

### Auth & multi-tenancy reminders (load-bearing across every service)

Repeat your platform's non-negotiables here even if they also live in each service's CLAUDE.md — e.g. "never derive a tenant key from headers; verified token claims only" and "every DB query, API call, and cache key includes ALL keys from `tenancy.keys`" (see `multi-tenancy-checklist.md` and `jwt-checklist.md`).

---

## The reflection inbox (how warts get captured)

The toolkit ships a Stop-hook (`hooks/session-reflect.sh`) that, at the end of any substantial session, sends Claude back for one reflection turn to append any non-obvious gotcha the session uncovered to an **inbox** file — `known-warts-inbox.md` — for later human review and promotion into this registry. Entries land in the inbox, never directly here; you curate the promotions.

Knobs (env vars):

- `AIF_REFLECT_OFF=1` — disable reflection (per-session, per-repo via `.claude/settings.local.json` env, or per-developer in your shell profile)
- `AIF_REFLECT_MIN_EDITS` — minimum Edit/Write tool uses before a session counts as substantial (default 3)
- `AIF_REFLECT_INBOX` — override the inbox path (default `~/.claude/aif-references/known-warts-inbox.md`)

Periodically sweep the inbox: promote real warts into the tables above, discard the rest.

---

## Adding to this file

Lean and append-only. Format:

```markdown
| YYYY-MM-DD | Wart in one line | What to do / why it matters |
```

Trigger to add: you spent more than 15 minutes debugging something that was "obvious in retrospect" because the code didn't tell you. Write it down so the next person doesn't repeat the loop. If a wart later gets fixed, **delete the entry** rather than annotate — this file decays poorly if it accumulates stale fixes.

If you find yourself writing more than a one-liner, you're documenting a feature, not a wart. Put it in the relevant `CLAUDE.md` or a reference doc instead.
