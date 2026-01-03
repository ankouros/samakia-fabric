# Runtime Operations (Phase 14)

Runtime operations are evidence-driven and read-only by default.
No automation performs remediation or execution.

## Inputs (approved only)

- Drift evidence: `evidence/drift/**`
- Binding verification outputs: `evidence/bindings-verify/**`
- SLO declarations: `contracts/tenants/<tenant>/slo/*.yml`
- Observation policy: `contracts/runtime-observation/observation.yml`

## Classification workflow

1) Collect the latest evidence for the tenant/workload.
2) Classify using the runtime signal taxonomy:
   - Infrastructure Fault
   - Drift
   - SLO Violation
3) Record the decision and supporting evidence.

Classification order is strict and deterministic. Do not mix categories.

## How to run runtime evaluation

Run evaluation (read-only):

```bash
make runtime.evaluate TENANT=<id|all>
```

Update status summaries from latest evidence:

```bash
make runtime.status TENANT=<id|all>
```

## SLO evaluation (Phase 14 Part 2)

SLO measurement and alert readiness are documented in `docs/operator/slo.md`.

Offline ingestion (CI-safe):

```bash
make slo.ingest.offline TENANT=<id|all>
```

Evaluate SLOs and generate evidence:

```bash
make slo.evaluate TENANT=<id|all>
```

Generate alert readiness rules (delivery disabled):

```bash
make slo.alerts.generate TENANT=<id|all>
```

## Evidence layout

```
evidence/runtime-eval/<tenant>/<workload>/<UTC>/
  inputs/
    drift.json
    verify.json
    slo.yml
    observation.yml
  evaluation.json
  classification.json
  summary.md
  manifest.sha256
```

Evidence is redacted, deterministic, and secrets-free.

Runtime status summaries are written to:

```
artifacts/runtime-status/<tenant>/<workload>/
  status.json
  status.md
```

## Escalation guidance

- Infrastructure Fault: notify platform operations and substrate owners.
- Drift: notify contract owners and verify intended state.
- SLO Violation: notify the SLO owner (operator or tenant).

## What not to do

- Do not auto-remediate.
- Do not change infrastructure from CI.
- Do not write secrets into evidence or logs.
- Do not reclassify signals without new evidence.
