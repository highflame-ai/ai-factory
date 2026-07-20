# Telemetry Pipeline Map (fill-in template)

A template for documenting any multi-hop metrics/scan telemetry pipeline so that "results are missing from the dashboard" debugging is a checklist, not archaeology. Fill it in per pipeline your org runs; link the ADR that motivated the design if one exists (`org.adr_dir` in `.aif/config.yml`; skip the link if absent).

Why this doc shape works: telemetry pipelines fail silently — every hop has a "accepted but dropped" mode — so the map names each hop and the debug checklist gives one observable question per hop, in order.

## The pipeline in one block (worked example)

A typical shape: producer daemon → ingest gateway → trace collector → warehouse → materialized views → dashboards.

```
Producer daemon (retrying ingestor: local retry queue + dead-letter)
  -> POST /v1/telemetry/{scan-results, inventory, coverage}   (202, telemetry-only, tenant from JWT)
  -> Gateway emits OTLP spans over gRPC (OTEL_EXPORTER_OTLP_ENDPOINT; no-op if telemetry disabled)
       event_type attribute: scan_summary* | scan_finding | inventory | coverage
       (*summary span deliberately NOT persisted)
  -> Collector -> warehouse raw-span table (write-through only, stores nothing itself)
  -> materialized views -> typed tables (scan_results, scan_findings, inventory, ...)
  -> query API -> dashboards
```

Replace with your real hops. For each hop record: the transport, the success signal (status code / counter), the config that can silently disable it, and where dropped data goes.

## Debug checklist — one question per hop, in order

1. **Producer shipped it?** Check the daemon's retry queue / dead-letter files; know the schedule (e.g. scans at startup, coverage every N minutes, event-driven with a TTL cache).
2. **Gateway accepted it?** Ingest should return a body you can interpret (e.g. `202` with `{status, spans_emitted}`); `spans_emitted: 0` means the payload decoded to nothing. A missing tenant claim in the JWT should be a 401, not a silent drop.
3. **Spans actually emitted?** Telemetry exporters often default OFF locally (a disabled flag or unset `OTEL_EXPORTER_OTLP_ENDPOINT` makes the tracer a silent no-op). Verify the flag AND the endpoint.
4. **Rows in the warehouse?** Query the typed destination table directly, not the raw write-through table (which may be configured to store nothing). Filter by your tenant keys (`tenancy.keys`).
5. **Materialized view intact?** Inspect the view definition (`SHOW CREATE TABLE`-equivalent); it must read the raw table and filter the right event type. A rebuilt-from-stale-body view is the classic silent breakage.

## Adding a queryable field (worked example)

1. **Gateway:** emit the new span attribute where telemetry spans are constructed.
2. **Warehouse:** one migration that adds the typed column AND rebuilds the materialized view. Prefer an in-place SELECT swap (e.g. ClickHouse `ALTER TABLE ... MODIFY QUERY` — no unforwarded-insert window); use DROP VIEW + ADD COLUMN + CREATE VIEW only when the target layout changes, accepting that rows arriving during the DROP window are lost.
3. Decide up front whether typed tables also keep the raw attribute map; if they don't, a field that wasn't promoted to a column is gone.

## Gotchas worth documenting for your pipeline

- **View exclusion rules:** if a general-purpose view and a telemetry-specific view read the same raw table, the general one must EXCLUDE the telemetry event-type family, or telemetry pollutes your aggregates. When rebuilding a view, always re-derive from the latest view body, never a stale copy.
- **Discriminator attribute:** stamp every telemetry span with a marker attribute (e.g. `decision_engine = 'telemetry'`) so ad-hoc queries can separate telemetry from real traffic.
- **Ingest limits:** document the max body size and decode posture (e.g. 32 MiB cap; bad JSON = 400, missing optional fields tolerated).
