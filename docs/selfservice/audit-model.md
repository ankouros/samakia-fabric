# Self-Service Evidence & Audit Model (Phase 15 Part 2 — Design)

This document defines the evidence model for self-service proposals.
No execution tooling is introduced in this phase.

## Evidence roots

```
evidence/selfservice/<tenant>/<proposal_id>/
  submit/
  validate/
  review/
  approve/
  delegate/
  execute/        # future phase
```

## Required artifacts by stage

### submit/
- `proposal.yml`
- `checksum.sha256`

### validate/
- `validation.json`
- `manifest.sha256`

### review/
- `diff.md`
- `impact.json`
- `plan.json`
- `summary.md`
- `manifest.sha256`

### approve/
- `approval.yml`
- `approval.sha256`
- `approval.sig` (prod only)

### delegate/
- `delegation.yml`
- `delegation.sha256`

### execute/ (future)
- `execution.json`
- `execution.sha256`
- `execution.sig` (prod only)

## Hashing and signing

- Every stage produces a `manifest.sha256` or `*.sha256` for integrity.
- Prod approvals and executions require signatures (`*.sig`).
- Evidence files are secrets-free and tenant-readable.

## Retention policy (design)

- Minimum retention: 180 days for non-prod, 365 days for prod.
- Legal hold overrides retention.
- Evidence is append-only; no in-place edits.
