# Binding Secret Cutover (Phase 17 Step 5)

This contract defines a **secret cutover** plan for binding consumers. It is
metadata-only and contains **no secret values**.

## Intent

Cutover updates a binding from an old `secret_ref` to a new `secret_ref` and
verifies connectivity. It is operator-controlled, guarded, and reversible.

## Rules

- No secret values in cutover files.
- Cutover is explicit and single-workload scoped.
- Live verification requires explicit guard flags; CI remains read-only.
- Production cutovers require change windows and evidence signing.

## Files

- Schema: `contracts/rotation/cutover.schema.json`
- Examples: `contracts/rotation/examples/`
- Operator runbook: `docs/operator/secrets-rotation.md`
