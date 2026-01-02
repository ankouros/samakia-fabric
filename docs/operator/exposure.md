# Operator Exposure Workflow (Phase 13)

This document is the **canonical operator UX** for governed workload exposure.
Exposure writes **artifacts only** and never provisions substrate resources.

## Preconditions

- Phase 11 hardening accepted.
- Phase 12 closure accepted (readiness packet exists).
- Milestone Phase 1-12 lock present.
- Exposure policy validated.

## 1) PLAN (read-only)

Generate a deterministic plan and evidence. No artifacts are written.

```bash
TENANT=canary WORKLOAD=sample ENV=samakia-dev make exposure.plan
```

Optional plan explanation:

```bash
TENANT=canary WORKLOAD=sample ENV=samakia-dev make exposure.plan.explain
```

Outputs:
- Evidence: `evidence/exposure-plan/<tenant>/<workload>/<UTC>/`

## 2) APPROVE (operator decision)

Create an approval artifact referencing the plan evidence. For prod, approvals
must be signed and include a change window.

```bash
TENANT=canary WORKLOAD=sample ENV=samakia-dev \
  APPROVER_ID="ops-001" EXPOSE_REASON="canary exposure" \
  make exposure.approve
```

## 3) APPLY (guarded)

Apply writes exposure artifacts only. Execution is guarded and opt-in.

```bash
EXPOSE_EXECUTE=1 EXPOSE_REASON="canary exposure" APPROVER_ID="ops-001" \
ENV=samakia-dev TENANT=canary WORKLOAD=sample \
make exposure.apply
```

Prod requires:
- `CHANGE_WINDOW_START` + `CHANGE_WINDOW_END`
- `EXPOSE_SIGN=1`
- Signed approval artifact

Artifacts:
- `artifacts/exposure/<env>/<tenant>/<workload>/`

Evidence:
- `evidence/exposure-apply/<tenant>/<workload>/<UTC>/`

## 4) VERIFY (read-only)

Verification is offline by default. Live verification requires explicit guard.

```bash
ENV=samakia-dev TENANT=canary WORKLOAD=sample make exposure.verify
```

Live verification (operator-only):

```bash
VERIFY_LIVE=1 ENV=samakia-dev TENANT=canary WORKLOAD=sample make exposure.verify
```

## 5) ROLLBACK (guarded)

Rollback removes exposure artifacts and verifies baseline drift.

```bash
ROLLBACK_EXECUTE=1 ROLLBACK_REASON="canary window closed" \
ENV=samakia-dev TENANT=canary WORKLOAD=sample \
make exposure.rollback
```

## Blast Radius Strategy

- Start with a **canary tenant** in non-prod.
- One provider at a time.
- Timeboxed change windows.
- Mandatory rollback plan before apply.

See:
- `docs/exposure/semantics.md`
- `docs/exposure/rollback.md`
- `docs/exposure/change-window-and-signing.md`
