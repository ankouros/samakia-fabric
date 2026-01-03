# Self-Service Proposal Review (Phase 15 Part 1)

Self-service proposals are **tenant-submitted, read-only** change requests.
Operators review evidence, evaluate policy requirements, and decide whether to
proceed with any execution (outside Phase 15 Part 1).

## Quick commands

```bash
# Review bundle (validation + diff + impact + plan)
make selfservice.review PROPOSAL_ID=<id>

# Plan only (read-only)
make selfservice.plan PROPOSAL_ID=<id>
```

## Evidence layout

Review bundles live under:
`evidence/selfservice/<tenant>/<proposal_id>/`

Files:
- `proposal.yml` — submitted proposal
- `validation.json` — schema + semantic validation
- `diff.md` — desired changes vs current contracts
- `impact.json` — providers, capacity delta, SLO/drift risk
- `plan.json` — read-only plan preview + policy requirements
- `summary.md` — operator summary
- `manifest.sha256` — evidence integrity hash list

## Review checklist

- Proposal is valid and unexpired (`validation.json` PASS).
- Scope is allowed (bindings/capacity/exposure intent only).
- Capacity deltas are positive (increase-only).
- Exposure requests are intent-only and policy compliant.
- Policy requirements (approvals/signing/change window) are clear.

## Operator responsibility

- **Do not** apply changes in Phase 15 Part 1.
- Capture required approvals before any execution in later phases.
- Keep evidence packets intact for auditability.

See also:
- `docs/operator/cookbook.md`
- `docs/tenants/selfservice.md`
