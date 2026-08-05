# Adding a pack to the registry

This directory is the codeoid **pack registry**. A pack is **data, not code**: a
`pack.yaml` manifest plus the capability roles and constitution its phases run
under. codeoid loads a pack with `loadPack(dir)` and runs its pipeline via
`pipeline.create({ pack: "<id>" })`. Nothing executable travels with a pack, so
it is safe to fetch and inspect — see [README.md](README.md) for the concept.

Follow these steps to add a new pack. Keep it declarative; if you find yourself
wanting to ship a script, reference an installed skill by slash command instead.

## 1. Scaffold the directory

```
packs/<pack-id>/
  pack.yaml       # the manifest (required)
  ETHOS.md        # constitution, composed into every phase's prompt (optional but recommended)
  roles/          # one YAML per capability role your phases use
    *.yaml
  README.md       # human-facing: what the pack is, its phase table
```

`<pack-id>` must match `^[a-zA-Z0-9][a-zA-Z0-9._-]*$` (≤64 chars) and be unique
in this registry. Roles live **inside** the pack so it fully declares its own
governance — copy the ones you need from the repo-root `roles/` (don't symlink;
a pack must be self-contained).

## 2. Write `pack.yaml`

```yaml
schema: codeoid/pack@v1          # exact literal — the loader rejects anything else
id: <pack-id>
name: Human Readable Name
version: 0.1.0
description: >
  One or two sentences on what this methodology does.
constitution: ./ETHOS.md         # path, confined to the pack dir (no absolute / .. escapes)

roles:                           # paths to role files (see step 3)
  - ./roles/implementer.yaml
  - ./roles/reviewer.yaml

skills:                          # runnable content each phase drives
  - { id: spec,   kind: slash,  command: /spec }        # an installed ai-factory skill
  - { id: note,   kind: prompt, template: "Do X, then Y." }  # or an inline prompt

gates:                           # pass/fail predicates (see "Gate kinds" below)
  - { id: tests_pass, kind: command, run: "make test" }

phases:                          # the pipeline — at least one
  - { id: spec,   skill: spec, role: implementer,                   onFail: halt }
  - { id: review, skill: note, role: reviewer,    gate: tests_pass, onFail: { retry: 2 } }
```

**Field reference**
- `skills[]` — `{ id, kind }` where `kind: slash` needs `command` (an installed
  skill, e.g. `/spec`) and `kind: prompt` needs `template` (inline text — the
  loader takes the string verbatim, it is NOT a file path). A multi-line
  template is written as a block-mapping list item with a `|` literal scalar,
  which the registry's validator also accepts:

  ```yaml
  - id: verify
    kind: prompt
    template: |
      First line of the prompt.
      Second line.
  ```
- `gates[]` — see below. Referenced by a phase's `gate` (exit) or `entryGate`.
- `phases[]` — `id` (unique), `skill` (a `skills[]` id), `role` (a role name),
  optional `kind` (defaults to `skill` when `skill` is set; use `noop` for a
  gate-only step), optional `provider`/`model` (per-phase backend override),
  `gate`/`entryGate`, and `onFail`.
- `onFail` — `halt` (default; park for a human), `abort` (hard-fail), or
  `{ retry: <n> }` (re-run up to n times).

## 3. Write the roles (`roles/*.yaml`)

The **role IS the capability envelope** — this is the governance-critical part. A
phase runs under exactly one role; it compiles to Cedar and (soon) is enforced at
the tool fence, so a `reviewer` phase physically cannot write or egress.

```yaml
name: reviewer                   # referenced by phases as `role: reviewer`
summary: Read-only analysis; produces findings, never mutates the tree.
write: false                     # may the phase write files?
network: read-only               # false | read-only | true
envelope: [read, grep, glob, bash]   # "all" OR an explicit tool list
exceptions:                      # optional per-tool escalations
  gemini-reviewer:
    add: [edit, write]
    reason: applies accepted review-bot comments directly
```

## 4. Gate kinds

- `command` — `{ kind: command, run: "<shell>" }`. Runs on the host **only for a
  pack the operator has explicitly trusted** (`pipeline.packs[].trusted: true` in
  codeoid config). An untrusted pack fails command gates **closed** — it never
  executes host commands. Exit 0 = pass.
- `skill` / `self` / `review` — declared here but not yet enforced end-to-end;
  they currently **fail closed** (halt for a human) until the gate-execution
  slice lands. Never a silent pass.

Every gate takes an optional `at: entry | exit` (default `exit`).

## 5. Validate before you PR

A pack must load cleanly under codeoid's `loadPack` — it fails fast on schema,
unknown-skill, unknown-role, duplicate-phase, missing-kind, and path-escape
errors. With a codeoid checkout beside this repo:

```bash
# run from the codeoid repo root
bun -e 'import { loadPack } from "./src/daemon/pipeline/pack";
  const p = loadPack("<abs path>/packs/<pack-id>");
  console.log(p.id, Object.keys(p.roles), p.pipeline.map(x => x.id + "[" + x.role + "]"));'
```

Expect it to print your id, roles, and phase→role mapping with no throw.

## 6. Register + open the PR

Add a row to the table in [README.md](README.md), commit, and open a PR. Once
merged, any codeoid pointed at this registry can select the pack. Commit as your
Highflame identity; keep the pack data-only.

Worked example: [`aif-sdlc/`](aif-sdlc/) — the AIF spec-driven lifecycle.
