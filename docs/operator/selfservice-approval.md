# Self-Service Approval & Delegation (Phase 15 Part 2 — Design)

This document describes the **design-only** operator workflow for approving and
 delegating self-service proposals. **No execution tooling is implemented** in
Phase 15 Part 2.

## Review before approval

- Confirm proposal validation PASS.
- Check diff/impact for scope drift or oversized capacity deltas.
- Ensure requested environment is allowed.
- Confirm proposal is unexpired.

## Approval semantics

- Approval is **explicit** and scoped.
- Approval is **necessary but not sufficient** for execution.
- Prod approvals require change windows and signatures.

## Delegation semantics

- Delegation is **time-bound** and revocable.
- Delegation **never grants secret access**.
- Delegation does not bypass Phase 13 policy checks.

## Design-only example commands (not implemented)

```bash
# Design-only: create approval artifact (no tooling implemented)
selfservice-approve \
  --proposal example \
  --approved-by ops-01 \
  --scope bindings,capacity,exposure_intent \
  --env samakia-dev \
  --expiration 2026-02-01T00:00:00Z \
  --change-window change-window/2026-01-03 \
  --signature signatures/approval-example.asc

# Design-only: delegate execution window (no tooling implemented)
selfservice-delegate \
  --proposal example \
  --operator-role platform-operator \
  --actions plan,apply \
  --valid-from 2026-01-03T00:00:00Z \
  --valid-until 2026-01-03T06:00:00Z \
  --env samakia-dev
```

## Revoke or expire

- Approvals and delegations can be revoked by removing or superseding the
  artifact and recording a revocation note in evidence.
- Expired approvals/delegations are **terminal** and must not be reused.

## What not to approve

- Requests that widen scope beyond the proposal.
- Capacity increases without quantified deltas.
- Exposure intent without required change windows (prod).
- Any proposal containing secrets or credential material.

See also:
- `docs/selfservice/proposal-lifecycle.md`
- `docs/selfservice/execution-mapping.md`
- `docs/selfservice/audit-model.md`
