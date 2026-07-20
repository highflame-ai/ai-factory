# Packs

Codeoid **packs** — a shared registry of AI-SDLC methodologies.

A pack is a directory of **data**, never code: a `pack.yaml` manifest plus the
capability roles and constitution it governs its phases with.
Codeoid reads a pack with `loadPack(dir)` (contract: `schema: codeoid/pack@v1`)
and can run its pipeline with `pipeline.create({ pack: "<id>" })`.
Because nothing executable travels with a pack, a pack is safe to fetch and
inspect; whether a pack's `command` gates actually run on a host is a separate
trust decision that defaults to off.

The point of this directory: **contribute a methodology once, and any team can
select it.** Add a new pack as a sibling directory, open a PR, and it becomes
available to every codeoid that points at this registry.

| Pack | What it is |
|------|------------|
| [`aif-sdlc/`](aif-sdlc/) | Spec → architect → implement → review → ship, governed per phase. The AIF spec-driven lifecycle, expressed as a codeoid pack. |

## Anatomy of a pack

```
<pack-id>/
  pack.yaml       # the manifest (schema: codeoid/pack@v1)
  ETHOS.md        # constitution — composed into every phase's system prompt
  roles/          # capability roles → Cedar; each phase runs under exactly one
    *.yaml
```

Roles live **inside** the pack, so a pack fully declares what its phases may do
(the reviewer role can't write or egress; the implementer role can). Skills are
referenced by slash command — their content is installed where the agent runs
(here, from this repo's `skills/`), keeping the pack itself data-only.

See [`aif-sdlc/pack.yaml`](aif-sdlc/pack.yaml) for a worked example.
