# Self-Service Risk Ledger (Phase 15 Part 5 — Design)

The risk ledger is a design-only record of operational risk introduced by
self-service approvals.

## What the ledger records

- Approved proposals and scope/magnitude.
- Incidents or rollbacks following approvals.
- SLO impact and drift observations after changes.
- Approval dates, approvers, and evidence links.

## What the ledger is not

- Not billing or quota accounting.
- Not a replacement for incident records.

## How it is used (design)

- Inform autonomy unlock decisions.
- Detect patterns that suggest guardrail adjustments.
- Provide governance evidence during reviews.

## Statement

The risk ledger is operational risk accounting, not a service charge model.
