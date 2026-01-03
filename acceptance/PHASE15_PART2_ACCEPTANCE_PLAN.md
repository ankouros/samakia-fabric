# Phase 15 Part 2 Acceptance Plan (Design Only)

This plan defines how to **validate the design** for approval and delegation
without introducing execution tooling.

## Synthetic walkthrough (design-only)

1. Start from an existing proposal (`examples/selfservice/example.yml`).
2. Validate → review evidence exists (Phase 15 Part 1 tooling).
3. Create **approval artifact** (design-only):
   - Populate `contracts/selfservice/approval.yml.example` with proposal ID.
4. Create **delegation artifact** (design-only):
   - Populate `contracts/selfservice/delegation.yml.example` with proposal ID.
5. Verify expected evidence locations and naming (see audit model).

## Expected evidence per stage (design-only)

- `submit/`: proposal + checksum
- `validate/`: validation.json + manifest
- `review/`: diff, impact, plan, summary, manifest
- `approve/`: approval.yml + hashes (+ signature in prod)
- `delegate/`: delegation.yml + hashes

## No execution performed

- No apply/rollback steps are run.
- No secrets are materialized.
- CI remains read-only.

## PASS/FAIL criteria

PASS if:
- All design documents and schemas exist.
- Approval/delegation examples align with schemas.
- Audit model describes evidence paths and hashing.
- No execution tooling is added.

FAIL if:
- Any required artifact is missing.
- Schemas omit required fields.
- Execution or automation tooling is introduced.
