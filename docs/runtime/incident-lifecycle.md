# Runtime Incident Lifecycle (Design)

Runtime incidents are managed as a deterministic, evidence-driven workflow.
No automation executes changes.

## Lifecycle stages

1) Detection
- A runtime signal arrives from approved evidence sources.

2) Classification
- Classify the signal as Drift, SLO Violation, or Infrastructure Fault.
- Do not mix classifications.

3) Evidence collection
- Gather inputs, evaluation results, and operator notes.
- Preserve deterministic manifests.

4) Decision
- Decide one of: no action, investigate, or rollback (if exposure artifacts exist).
- Any action is operator-controlled and documented.

5) Closure
- Record the outcome and close the incident.

## Decision tree (read-only, no automation)

- If substrate is unreachable or TLS fails, classify as Infrastructure Fault.
- Else if declared state differs from observed state, classify as Drift.
- Else if SLO thresholds are violated, classify as SLO Violation.
- Else, classify as OK and record no action.

## Evidence layout (design only)

Runtime evidence packets are written under:

```
evidence/runtime/<tenant>/<workload>/<UTC>/
  signals.json
  classification.json
  slo-evaluation.json
  decision.md
  manifest.sha256
```

Evidence is redacted, deterministic, and secrets-free.
