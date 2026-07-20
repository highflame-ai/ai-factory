# Migration Safety Checklist

What `migration-analyzer` grades against. Use this when authoring or reviewing any SQL migration that runs against a shared or production Postgres (including managed flavors like Aurora/RDS/Cloud SQL).

## The five questions every migration must answer

1. **Is it idempotent?** Can it run twice without breaking?
2. **Will it lock?** What's the worst-case lock duration on a multi-million-row table?
3. **What's the rollback plan?** If it goes sideways at 2am, what does the on-call do?
4. **Does it backfill?** If it adds NOT NULL or new derived data, how is it populated?
5. **Is it tenant-safe?** Does it preserve the tenant-key invariants from `tenancy.keys` in `.aif/config.yml`? (If `tenancy.keys` is absent, note that and skip the tenancy checks.)

## DDL checklist

- [ ] `CREATE TABLE IF NOT EXISTS` (idempotent)
- [ ] `CREATE INDEX IF NOT EXISTS`
- [ ] `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` (Postgres 9.6+)
- [ ] `DROP COLUMN` is **two migrations** — first stop writing/reading the column in code, ship that, **then** drop in a follow-up
- [ ] `ALTER COLUMN ... SET NOT NULL` is **two migrations** — backfill first (separate migration), then SET NOT NULL once the table is clean
- [ ] New indexes use `CREATE INDEX CONCURRENTLY` on tables larger than ~100k rows
- [ ] Multi-tenant tables get indexes starting with the tenant keys, e.g. `(<tenant-key-1>, <tenant-key-2>, ...)`; partial `WHERE is_active` if soft-deletes apply

## Locking hazards (Postgres)

| Operation                              | Lock                               | Mitigation                                           |
| -------------------------------------- | ---------------------------------- | ---------------------------------------------------- |
| `ADD COLUMN` with no default           | ACCESS EXCLUSIVE, fast             | Safe                                                 |
| `ADD COLUMN ... DEFAULT 'x'` (PG 11+)  | ACCESS EXCLUSIVE, fast             | Safe — default stored in catalog, not rewritten      |
| `ADD COLUMN ... NOT NULL` (no default) | ACCESS EXCLUSIVE                   | **Don't.** Add nullable, backfill, then SET NOT NULL |
| `ALTER COLUMN ... TYPE` (incompatible) | Full table rewrite                 | Avoid; use new column + backfill + swap              |
| `CREATE INDEX` (without CONCURRENTLY)  | SHARE                              | Blocks writes for the duration                       |
| `CREATE INDEX CONCURRENTLY`            | None (rolling)                     | Safe; cannot run inside a transaction                |
| `DROP CONSTRAINT`                      | ACCESS EXCLUSIVE, fast             | Safe                                                 |
| `ADD FOREIGN KEY` (validated)          | SHARE ROW EXCLUSIVE on both tables | Use `NOT VALID` then `VALIDATE CONSTRAINT` later     |
| `VACUUM FULL`                          | ACCESS EXCLUSIVE                   | Never in a migration                                 |

## Backfill checklist

When a column is added that needs population:

- [ ] Backfill is its own migration (or a script run between migrations)
- [ ] Batched, not single-statement (e.g. `UPDATE ... LIMIT 1000` loop in a script, or `pg_repack` for big rewrites)
- [ ] Includes a sleep/yield between batches to keep replication lag bounded
- [ ] Idempotent (re-runnable if interrupted)
- [ ] Has a verification query — a follow-up migration's first statement should `SELECT COUNT(*) WHERE new_col IS NULL` and fail loudly if non-zero

## Rollback checklist

- [ ] Migration has a corresponding "down" file (e.g. golang-migrate's `*.down.sql`, or your tool's equivalent)
- [ ] Down is **only** safe if the up is reversible without data loss; document if it isn't
- [ ] Down works against a partially-applied up (e.g. if up failed mid-way)
- [ ] **Irreversible operations** (DROP COLUMN, DROP TABLE) document the data-loss boundary in a comment

## Multi-tenancy checklist

Only if `tenancy.keys` is configured (skip otherwise, and say so):

- [ ] New tables include every tenant-key column, NOT NULL (e.g. `account_id TEXT NOT NULL`, `project_id UUID NOT NULL`)
- [ ] New indexes start with the tenant keys for query patterns
- [ ] Backfills preserve tenant boundaries (e.g. `UPDATE ... WHERE <tenant-key-1> = ...` per tenant, not global)

## Verification (after the migration runs)

If an MCP server is configured (`mcp.namespace` in `.aif/config.yml`), use its read-only DB tools (see `mcp-tools-cheatsheet.md`). Otherwise use `psql` against the target environment, or say verification is manual:

- [ ] Describe the table — confirm column / index landed with the expected definition
- [ ] `SELECT COUNT(*) WHERE new_col IS NULL` — confirm backfill complete
- [ ] `EXPLAIN` the new query path — confirm the new index is used

## Red flags

- A migration that runs longer than 30s on a table > 1M rows (you're locking; rewrite)
- An `ALTER COLUMN ... SET NOT NULL` and an `UPDATE ... SET col = ...` in the same migration (lock + rewrite combo, will hurt)
- A new index without `CONCURRENTLY` on a hot table
- "We'll backfill in code" — backfills are migrations, not application logic
- A down migration that drops data without comment

## When you find an unsafe migration

If it's already in `main` but not yet applied to staging/prod:

1. Open a follow-up PR that supersedes it (revert + re-author)
2. Notify whoever's about to deploy

If it's already applied to a shared dev environment but not higher:

1. Forward-fix in the next migration
2. `migration-analyzer` should grade the forward-fix; do not silently merge
