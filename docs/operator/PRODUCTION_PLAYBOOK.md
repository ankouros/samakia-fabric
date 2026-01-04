# Production Playbook (Authoritative)

This playbook defines the single, production-approved operator workflow for
Samakia Fabric. It is the only supported "happy path" for production operations.

Rules:
- All commands are copy/paste friendly.
- No alternatives are listed unless explicitly labeled.
- Execute flags are always explicit.
- Every workflow ends with Expected evidence.

---

## Pre-flight: Verify platform health

```bash
RUNNER_MODE=ci make platform.regression
```

Expected evidence:
- None (regression output only; evidence index is validated in place).

---

## Canary exposure (Phase 17 Step 4)

```bash
make exposure.plan ENV=samakia-dev TENANT=canary WORKLOAD=sample

make exposure.approve \
  ENV=samakia-dev \
  TENANT=canary \
  WORKLOAD=sample \
  APPROVER_ID=ops-01 \
  REASON="Phase17 canary exposure test"

EXPOSE_EXECUTE=1 \
EXPOSE_REASON="Phase17 canary exposure execution" \
make exposure.apply ENV=samakia-dev TENANT=canary WORKLOAD=sample

VERIFY_LIVE=1 make exposure.verify ENV=samakia-dev TENANT=canary WORKLOAD=sample

ROLLBACK_EXECUTE=1 \
ROLLBACK_REASON="Phase17 mandatory rollback" \
make exposure.rollback ENV=samakia-dev TENANT=canary WORKLOAD=sample
```

Expected evidence:
- `evidence/exposure-plan/canary/sample/<UTC>/`
- `evidence/exposure-approve/canary/sample/<UTC>/`
- `evidence/exposure-apply/canary/sample/<UTC>/`
- `evidence/exposure-verify/canary/sample/<UTC>/`
- `evidence/exposure-rollback/canary/sample/<UTC>/`
- `evidence/exposure-canary/canary/sample/<UTC>/`

---

## Normal exposure (Phase 13)

```bash
make exposure.plan ENV=<env> TENANT=<tenant> WORKLOAD=<workload>

make exposure.approve \
  ENV=<env> \
  TENANT=<tenant> \
  WORKLOAD=<workload> \
  APPROVER_ID=ops-01 \
  REASON="Routine exposure"

EXPOSE_EXECUTE=1 \
EXPOSE_REASON="Approved exposure execution" \
make exposure.apply ENV=<env> TENANT=<tenant> WORKLOAD=<workload>

VERIFY_LIVE=1 make exposure.verify ENV=<env> TENANT=<tenant> WORKLOAD=<workload>

ROLLBACK_EXECUTE=1 \
ROLLBACK_REASON="Mandatory rollback after exposure" \
make exposure.rollback ENV=<env> TENANT=<tenant> WORKLOAD=<workload>
```

Expected evidence:
- `evidence/exposure-plan/<tenant>/<workload>/<UTC>/`
- `evidence/exposure-approve/<tenant>/<workload>/<UTC>/`
- `evidence/exposure-apply/<tenant>/<workload>/<UTC>/`
- `evidence/exposure-verify/<tenant>/<workload>/<UTC>/`
- `evidence/exposure-rollback/<tenant>/<workload>/<UTC>/`

---

## Secrets rotation cutover (Phase 17 Step 5)

```bash
make rotation.cutover.plan FILE=contracts/rotation/examples/cutover-nonprod.yml

ROTATE_EXECUTE=1 \
CUTOVER_EXECUTE=1 \
ROTATE_REASON="Rotate canary DB secret" \
make rotation.cutover.apply FILE=contracts/rotation/examples/cutover-nonprod.yml

ROLLBACK_EXECUTE=1 \
ROTATE_REASON="Rollback after cutover" \
CUTOVER_EVIDENCE_DIR="evidence/rotation/<tenant>/<workload>/<UTC>" \
make rotation.cutover.rollback FILE=contracts/rotation/examples/cutover-nonprod.yml
```

Expected evidence:
- `evidence/rotation/<tenant>/<workload>/<UTC>/`

---

## Runtime triage (Phase 14)

```bash
make runtime.evaluate TENANT=<tenant> WORKLOAD=<workload>
make runtime.status TENANT=<tenant> WORKLOAD=<workload>
```

Expected evidence:
- `evidence/runtime-eval/<tenant>/<workload>/<UTC>/`
- `artifacts/runtime-status/<tenant>/<workload>/`

---

## AI-assisted analysis (Phase 16)

```bash
make ai.analyze.plan FILE=examples/analysis/drift_explain.yml

AI_ANALYZE_EXECUTE=1 \
make ai.analyze.run FILE=examples/analysis/drift_explain.yml
```

Expected evidence:
- `evidence/ai/analysis/<analysis_id>/<UTC>/`

---

## Rollback procedures

```bash
ROLLBACK_EXECUTE=1 \
ROLLBACK_REASON="Rollback exposure" \
make exposure.rollback ENV=<env> TENANT=<tenant> WORKLOAD=<workload>

ROLLBACK_EXECUTE=1 \
ROTATE_REASON="Rollback secret cutover" \
CUTOVER_EVIDENCE_DIR="evidence/rotation/<tenant>/<workload>/<UTC>" \
make rotation.cutover.rollback FILE=contracts/rotation/examples/cutover-nonprod.yml
```

Expected evidence:
- `evidence/exposure-rollback/<tenant>/<workload>/<UTC>/`
- `evidence/rotation/<tenant>/<workload>/<UTC>/`

---

## Emergency freeze / kill switches

```bash
export RUNNER_MODE=ci
unset AI_ANALYZE_EXECUTE AI_INDEX_EXECUTE AI_REMEDIATE
export AI_ANALYZE_DISABLE=1
export AI_ANALYZE_BLOCK_TYPES="plan_review,change_impact"
export AI_ANALYZE_BLOCK_MODELS="gpt-oss:20b"
```

Expected evidence:
- None (environment-only safety switch).
