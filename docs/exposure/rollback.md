# Exposure Rollback

Rollback is a **first-class, mandatory step** for any exposure workflow.
It removes or disables exposure artifacts and verifies that the workload
returns to the pre-exposure baseline.

## Rollback Intent

- Remove exposure artifacts only.
- Do not modify substrate infrastructure.
- Do not materialize or revoke secrets outside existing policies.

## Decision Tree

1) Exposure artifacts are incorrect or unsafe -> rollback immediately.
2) Drift snapshot shows unexpected changes -> rollback and investigate.
3) Change window ends without verification completion -> rollback.

## Guarded Execution

Rollback is guarded and requires explicit flags. For prod, signing and
change window validation are mandatory.

```bash
ROLLBACK_EXECUTE=1 ROLLBACK_REASON="window closed" \
ROLLBACK_REQUESTED_BY="ops-001" \
ENV=samakia-dev TENANT=canary WORKLOAD=sample \
make exposure.rollback
```

Prod additionally requires `CHANGE_WINDOW_START`, `CHANGE_WINDOW_END`,
`EXPOSE_SIGN=1`, and `EVIDENCE_SIGN_KEY`.

## Evidence

Rollback must produce evidence under:

- `evidence/exposure-rollback/<tenant>/<workload>/<UTC>/`

Include:
- rollback intent
- verification steps executed
- drift snapshot
- manifest hashes (signed for prod)
