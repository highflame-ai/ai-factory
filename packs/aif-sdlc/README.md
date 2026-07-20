# aif-sdlc

The AIF spec-driven lifecycle, expressed as a codeoid pack
(`schema: codeoid/pack@v1`). Selecting this pack runs a requirement through five
governed phases:

| Phase | Skill | Role | Exit gate | On fail |
|-------|-------|------|-----------|---------|
| spec | `/spec` | implementer | `spec_valid` (`/validate`) | halt |
| architect | `/architect` | implementer | `spec_valid` | halt |
| implement | `/proceed` | implementer | `tests_pass` (`make test`) | retry ×2 |
| review | `/review` | reviewer | `no_blocking_findings` | halt |
| ship | `/wrapup` | orchestrator | — | — |

## Why the role matters

The **role is the capability envelope**, not a label. Each phase runs under
exactly one role (`roles/*.yaml`), which compiles to Cedar and is enforced at
the tool fence:

- **implementer** — `write: true`, network read-only, full tool envelope.
- **reviewer** — `write: false`, network read-only, envelope `[read, grep, glob, bash]`.
  The review phase *physically cannot* mutate the tree or egress.
- **orchestrator** — `write: true`, network `true` (PR/forge APIs, configured MCP).

So the governance isn't a prompt suggestion — a reviewer phase that tries to
write is denied at runtime. (Runtime enforcement wires role → Cedar → Shield as
a follow-on; the pack carries the capability today.)

## Constitution

[`ETHOS.md`](ETHOS.md) is composed into every phase's system prompt — the
non-negotiable engineering ethos the whole pipeline runs under.

## Gates

- `spec_valid` — the `/validate` skill checks a phase's output before advancing.
- `tests_pass` — a `command` gate (`make test`). It runs **only** for a pack the
  host has explicitly trusted; an untrusted pack fails it closed.
- `no_blocking_findings` — the read-only review bench must return no blockers.

`skill` / `review` gates are declared here but not yet enforced end-to-end; they
fail closed (halt for a human) until the gate-execution slice lands. Never a
silent pass.
