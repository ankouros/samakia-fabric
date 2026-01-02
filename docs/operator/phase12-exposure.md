# Phase 12 Exposure — One-Page Operator Flow

This page is the canonical happy path to declare workload exposure readiness.

## Scope

- Read-only by default.
- CI remains read-only; no execute paths are allowed in CI.
- Secrets are never written to Git or evidence.

## Happy path (read-only)

### 1) Validate pre-exposure hardening (Phase 11)
```bash
make phase11.hardening.entry.check
make phase11.hardening.accept
```

### 2) Validate bindings (Phase 12 Part 1)
```bash
make bindings.validate TENANT=all
make bindings.render TENANT=all
```

### 3) Inspect secret refs (Phase 12 Part 2)
```bash
make bindings.secrets.inspect TENANT=all
```

### 4) Run offline verify (Phase 12 Part 3)
```bash
make bindings.verify.offline TENANT=all
```

### 5) Run drift snapshot (Phase 12 Part 5)
```bash
TENANT=all DRIFT_OFFLINE=1 DRIFT_NON_BLOCKING=1 DRIFT_FAIL_ON=none make drift.detect
TENANT=all make drift.summary
```

### 6) Generate readiness packet (Phase 12 Part 6)
```bash
TENANT=all make phase12.readiness.packet
```
For prod signing, set `READINESS_SIGN=1` and ensure a local GPG key; in CI, signing is skipped unless `READINESS_SIGN=1` is set.

### 7) Declare exposure allowed (Phase 12 acceptance)
```bash
make phase12.part6.accept
```

## Optional (operator-controlled)

### Proposal review flow (Phase 12 Part 4)
```bash
make proposals.validate PROPOSAL_ID=example
make proposals.review PROPOSAL_ID=add-postgres-binding
```

### Secret materialization / rotation (Phase 12 Part 2; guarded)
```bash
# Materialize (execute, guarded)
MATERIALIZE_EXECUTE=1 BIND_SECRETS_BACKEND=file \
BIND_SECRET_INPUT_FILE=./secrets-input.json \
make bindings.secrets.materialize TENANT=project-birds

# Rotate (execute, guarded)
ROTATE_EXECUTE=1 ROTATE_REASON="rotation plan" \
BIND_SECRETS_BACKEND=file ROTATE_INPUT_FILE=./rotation-input.json \
make bindings.secrets.rotate TENANT=project-birds
```

## CI notes (non-negotiable)

- CI is read-only; do not run live verify, approvals, or apply.
- Execute flags (BIND_EXECUTE, MATERIALIZE_EXECUTE, ROTATE_EXECUTE, PROPOSAL_APPLY) are blocked in CI.

## Outputs

- Readiness packet: `evidence/release-readiness/phase12/<UTC>/`
- Acceptance markers: `acceptance/PHASE12_PART6_ACCEPTED.md`, `acceptance/PHASE12_ACCEPTED.md`
