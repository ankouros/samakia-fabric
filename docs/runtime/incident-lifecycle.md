# Runtime Incident Lifecycle (Phase 14)

Runtime incidents are managed as a deterministic, evidence-driven workflow.
No automation executes changes.

## Lifecycle stages

1) Detection
- A runtime signal arrives from approved evidence sources.

2) Classification
- Classify the signal as Drift, SLO Violation, or Infrastructure Fault.
- Do not mix classifications.

3) Alert delivery (controlled)
- Alerts are generated from classified signals and SLO states.
- Delivery is explicit, guarded, and evidence-backed.
- CI never delivers alerts.

4) Evidence collection
- Gather inputs, evaluation results, alert outputs, and operator notes.
- Preserve deterministic manifests.

5) Decision
- Decide one of: no action, investigate, or rollback (if exposure artifacts exist).
- Any action is operator-controlled and documented.

6) Incident record
- Open/update/close incidents as bookkeeping records.
- Incident records do not modify infrastructure.

7) Closure
- Record the outcome and close the incident.

## Decision tree (read-only, no automation)

- If substrate is unreachable or TLS fails, classify as Infrastructure Fault.
- Else if declared state differs from observed state, classify as Drift.
- Else if SLO thresholds are violated, classify as SLO Violation.
- Else, classify as OK and record no action.

## Evidence layout

Runtime evidence packets are written under:

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

Alert evidence packets are written under:

```
evidence/alerts/<tenant>/<UTC>/
  signals.json
  slo.json
  routing.json
  decision.json
  delivery.json
  manifest.sha256
```

Incident records are written under:

```
evidence/incidents/<incident_id>/
  open.json
  updates/
  close.json
  manifest.sha256
```
