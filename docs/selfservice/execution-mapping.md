# Self-Service Execution Mapping (Phase 15 Part 2 — Design)

This document maps an **APPROVED + DELEGATED** self-service proposal to the
existing Phase 13 exposure execution model.

## Mapping overview

An approved + delegated proposal is **necessary but not sufficient** for
execution. Operators must still run Phase 13 workflows and policy checks.

| Proposal State | Phase 13 Action | Notes |
| --- | --- | --- |
| APPROVED + DELEGATED | `exposure.plan` | Required, read-only plan preview |
| APPROVED + DELEGATED | `exposure.apply` | Guarded execution with operator flags |
| APPROVED + DELEGATED | `exposure.rollback` | Guarded rollback with operator flags |

## Guard flags (design requirements)

- `EXPOSE_EXECUTE=1` required for apply execution.
- `ROLLBACK_EXECUTE=1` required for rollback execution.
- `VERIFY_LIVE=1` required for live verification.
- `PROPOSAL_APPLY` is **not** used by self-service flows.

## Required checks (re-run)

- Phase 13 policy evaluation (`exposure.policy.check`).
- Binding verification (offline by default; live only with guard).
- Change window validation for prod.
- Signature validation for prod approvals.

## Evidence reuse and generation

Reused evidence:
- Proposal validation, diff, impact, and plan evidence from Phase 15 Part 1.
- Approval and delegation artifacts.

New evidence:
- Phase 13 plan evidence packets (policy decision + plan diff).
- Apply/verify/rollback evidence packets.

## Prohibited shortcuts

- **Do not** skip Phase 13 policy evaluation.
- **Do not** reuse stale approvals or delegations beyond expiration.
- **Do not** execute without an active change window for prod.
