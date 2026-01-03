# SLO Measurement (Phase 14 Part 2)

SLO measurement is read-only and evidence-first.
This workflow evaluates declared objectives without remediation or alert delivery.

## Inputs (approved only)

- SLO contracts: `contracts/tenants/<tenant>/slo/*.yml`
- Observation policy: `contracts/runtime-observation/observation.yml`
- Offline fixtures (CI-safe): `fixtures/metrics/*.json`
- Live metrics (operator-only): Prometheus query_range (guarded)

Only metrics declared in the observation policy are used.

## Ingest metrics

Offline ingestion (CI-safe):

```bash
make slo.ingest.offline TENANT=<id|all>
```

Ingested metrics are written under `artifacts/slo-metrics/<tenant>/<workload>/`.

Live ingestion (operator-only; forbidden in CI):

```bash
PROM_URL=https://prom.example.net \
  PROM_QUERY_FILE=/path/to/prom-queries.json \
  make slo.ingest.live TENANT=<id|all>
```

Live ingestion uses Prometheus `query_range` only and requires explicit opt-in.
The `slo.ingest.live` target is guarded and will refuse to run in CI.

`PROM_QUERY_FILE` is a JSON object that maps observed metrics to PromQL
expressions. Optional `window_seconds` and `step_seconds` keys control the
query range window.

## Evaluate SLOs

```bash
make slo.evaluate TENANT=<id|all>
```

Evaluation uses the declared window (rolling or tumbling) and computes:
- objective burn rates
- error budget remaining
- per-objective state (OK / WARN / CRITICAL)

### Error budget semantics

- Availability and error rate budgets are treated as percent points.
- Latency budgets are computed as a percentage of the target latency.
- Burn rate = breach / budget.
- WARN when burn rate >= `severity.warn`.
- CRITICAL when burn rate >= `severity.critical` or the budget is exhausted.

Metrics missing from the observation policy are reported and treated as WARN.

## Evidence packets

Evidence is written to:

```
evidence/slo/<tenant>/<workload>/<UTC>/
  inputs/
    slo.yml
    metrics.json
    windows.json
  evaluation.json
  error_budget.json
  state.json
  summary.md
  manifest.sha256
  manifest.sha256.asc (prod if enabled)
```

Evidence is deterministic, redacted, and secrets-free.

## Status outputs

Operator summaries are written to:

```
artifacts/slo-status/<tenant>/<workload>/
  status.json
  status.md
```

## Alert readiness (disabled by default)

Generate alert rules (no delivery enabled):

```bash
make slo.alerts.generate TENANT=<id|all>
```

Outputs:

```
artifacts/slo-alerts/<tenant>/<workload>/
  rules.yaml
  manifest.sha256
```

Rules include tenant/workload labels and `delivery: disabled` by default.
Alert delivery enablement and routing is out of scope for Phase 14 Part 2 and
must be explicitly configured by operators later.

## Safety notes

- No remediation or scaling is performed.
- CI remains read-only.
- Alert delivery is disabled by default.
