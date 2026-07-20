# References

Loadable-on-demand checklists and templates. Skills and subagents reference these by path; they are NOT auto-loaded into every session.

Two kinds of file live here:

- **Ready-to-use checklists** — generic methodology that works as-is, parameterized by `.aif/config.yml` keys where org specifics matter.
- **Fill-in templates** (marked below) — scaffolding an org completes after adopting the toolkit, replacing the worked examples with its own tools, profiles, and pipelines.

## Index

| File                                                               | Kind             | Load when                                                                                                          |
| ------------------------------------------------------------------ | ---------------- | ------------------------------------------------------------------------------------------------------------------ |
| [`mcp-tools-cheatsheet.md`](./mcp-tools-cheatsheet.md)             | Fill-in template | About to investigate live state — map your MCP server's `mcp__<namespace>__*` tools (from `mcp.namespace`) to intents |
| [`multi-tenancy-checklist.md`](./multi-tenancy-checklist.md)       | Fill-in template | Touching DB queries, cache keys, API handlers — fill in your tenant keys (`tenancy.keys`) before first use         |
| [`jwt-checklist.md`](./jwt-checklist.md)                           | Fill-in template | Touching auth — enumerate your token types first, then apply the issuance/verification checklist per archetype     |
| [`migration-safety-checklist.md`](./migration-safety-checklist.md) | Checklist        | Authoring or reviewing a SQL schema/data migration; `migration-analyzer` agent grades against this                 |
| [`commit-prefix-check.md`](./commit-prefix-check.md)               | Checklist        | The commit-prefix hook fired, or you want to know how the configurable subject-line gate resolves its regex        |
| [`regression-markers.md`](./regression-markers.md)                 | Fill-in template | Picking a test profile (from `regression.profiles`) or markers for an org-level regression run                     |
| [`known-warts.md`](./known-warts.md)                               | Fill-in template | A CI gate looks broken or a test is mysteriously skipped — check the org's registry of known oddities first        |
| [`telemetry-pipeline.md`](./telemetry-pipeline.md)               | Fill-in template | Telemetry/scan results missing from a dashboard — document and debug a multi-hop metrics pipeline hop by hop       |
| [`trigger-recipes.md`](./trigger-recipes.md)                       | Recipe book      | Running skills autonomously — headless CI/cron recipes for /analyze, /review, /doc-drift, /dep-update, /release-notes |

## Why a separate folder

These are extracted from the workspace-level CLAUDE.md so we don't pay the context cost on every session. Skills reference them with an explicit `Read` of the file path, so the content lands only when relevant.

When updating: keep these tight. If a checklist grows past a screen, split it.
