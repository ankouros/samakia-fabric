# Phase 13 Acceptance Plan (Design)

Phase 13 introduces **governed exposure**. This plan is split into CI-safe
read-only validation and operator-run guarded execution.

## A) Read-only plan acceptance (CI-safe)

Required:
- Validate exposure policy schema and sample policies.
- Generate a synthetic plan output (no apply).
- Generate a redacted evidence packet.
- Ensure no secrets and TLS-only invariants.
- Confirm execute paths are guarded.

PASS criteria:
- Policy validation succeeds.
- Plan output includes artifact list and tags.
- Evidence packet exists with manifest hashes.
- No plaintext endpoints or secrets are present.

## B) Non-prod apply acceptance (operator-run)

Required:
- Apply exposure for a canary tenant in `samakia-dev` or `samakia-shared`.
- Run workload-side verification (read-only checks).
- Capture drift snapshot showing expected state.
- Rollback returns to baseline.

PASS criteria:
- Apply only writes exposure artifacts.
- Verify passes in offline mode (live optional with guard).
- Rollback evidence shows baseline restored.

## C) Prod readiness acceptance (plan-only)

Required:
- Demonstrate change window + signing are enforced.
- Plan only, no apply by default.
- Signed evidence packet references the plan output.

PASS criteria:
- Prod plan fails without change window/signing.
- Signed evidence packet generated when enabled.

## Evidence requirements

- Evidence must be redacted and secrets-free.
- Evidence includes manifest hashes (and signatures for prod).
- Evidence paths are gitignored.
