# Self-Service Proposal Contracts

This directory defines the tenant-facing contract for **self-service proposals**.
Self-service proposals are read-only requests that describe desired changes and
allow operators to review impact, policy alignment, and required approvals.

## Files

- `proposal.schema.json`: Schema for tenant-submitted self-service proposals.

## Rules

- Proposals are **proposal-only**; they never apply changes.
- Proposals **must not** include secrets or credentials.
- Capacity requests are **increase-only** and validated against current contracts.
- Exposure requests are **intent-only**; operators decide if/when to execute.
- Evidence is written under `evidence/selfservice/` (gitignored).

See also:
- `docs/tenants/selfservice.md`
- `docs/operator/selfservice-review.md`
