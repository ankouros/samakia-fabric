# Autonomy Audit Model (Design Only)

Every autonomy decision must be reconstructable after the fact. This model
defines the required evidence and audit expectations.

## Evidence structure

Each autonomy action emits a deterministic evidence packet:

```
evidence/ai/autonomy/<action_id>/<UTC>/
  decision.json
  preconditions.json
  action.json
  rollback.json
  logs.json
  summary.md
  manifest.sha256
```

## Required logs

- Decision rationale and trigger conditions.
- Preconditions verification results.
- Action execution summary.
- Rollback plan and outcome.
- Operator override events.

## Retention policy

- Minimum retention: 30 days locally.
- Audit retention: align with operational evidence policy.
- Evidence is read-only and redacted.

## Correlation

- Link decisions to incidents and SLO windows.
- Record any downstream alerts or rollbacks.
- Keep correlation IDs consistent across systems.
