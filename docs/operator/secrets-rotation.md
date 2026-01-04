# Secrets Rotation (Operator Cutover)

This runbook covers the **operator-controlled cutover** between binding secrets.
It complements Phase 12 secret materialization and keeps CI read-only.

## Scope

- Materialize new secrets (Phase 12 Part 2).
- Cut over bindings to the new `secret_ref` (Phase 17 Step 5).
- Verify connectivity (offline by default, live only when guarded).
- Roll back to the previous `secret_ref` if needed.
- Revocation of old credentials remains manual and is **out of scope**.

## Preconditions

- Binding contracts are valid and rendered.
- New secret material exists in the configured backend.
- Default backend is Vault; file backend requires `BIND_SECRETS_BACKEND=file` and passphrase config.
- `RUNNER_MODE=ci` (non-interactive) and operator-only execution.
- For prod, a change window and evidence signing are required.

## Cutover Plan (Read-only)

Plan a cutover and emit evidence without touching bindings.

```bash
make rotation.cutover.plan FILE=contracts/rotation/examples/cutover-nonprod.yml
```

Expected evidence:
- `evidence/rotation/<tenant>/<workload>/<UTC>/`
  - `cutover.yml.redacted`
  - `plan.json`
  - `diff.md`
  - `decision.json`
  - `verify.json`
  - `manifest.sha256`

## Cutover Apply (Guarded)

Apply the binding update and verify. Live verification requires explicit opt-in.

```bash
ROTATE_EXECUTE=1 \
CUTOVER_EXECUTE=1 \
ROTATE_REASON="Rotate canary DB credentials" \
make rotation.cutover.apply FILE=contracts/rotation/examples/cutover-nonprod.yml
```

Optional live verify:

```bash
ROTATE_EXECUTE=1 \
CUTOVER_EXECUTE=1 \
VERIFY_LIVE=1 \
ROTATE_REASON="Rotate canary DB credentials" \
make rotation.cutover.apply FILE=contracts/rotation/examples/cutover-nonprod.yml
```

Expected evidence (apply):
- `evidence/rotation/<tenant>/<workload>/<UTC>/`
  - `cutover.yml.redacted`
  - `plan.json`
  - `diff.md`
  - `decision.json`
  - `verify.json`
  - `manifest.sha256`

## Rollback (Guarded)

Rollback reverts binding files from the backup snapshot in evidence.

```bash
ROLLBACK_EXECUTE=1 \
ROTATE_REASON="Rollback cutover after failed verify" \
CUTOVER_EVIDENCE_DIR="evidence/rotation/<tenant>/<workload>/<UTC>" \
make rotation.cutover.rollback FILE=contracts/rotation/examples/cutover-nonprod.yml
```

Expected evidence (rollback):
- `evidence/rotation/<tenant>/<workload>/<UTC>/rollback.json`
- Updated `manifest.sha256`

## Production Requirements

Prod cutovers require a change window and evidence signing.

```bash
ROTATE_EXECUTE=1 \
CUTOVER_EXECUTE=1 \
ROTATE_REASON="Rotate prod DB credentials" \
EVIDENCE_SIGN=1 EVIDENCE_SIGN_KEY="ops-key" \
make rotation.cutover.apply FILE=contracts/rotation/examples/cutover-nonprod.yml
```

The cutover file must include `change_window.start` and `change_window.end`.

## What NOT to do

- Do not run cutover apply/rollback in CI.
- Do not bypass guard flags (`ROTATE_EXECUTE`, `CUTOVER_EXECUTE`, `ROLLBACK_EXECUTE`).
- Do not embed secret values in cutover files or evidence.
- Do not revoke old credentials during cutover (manual, separate workflow).
