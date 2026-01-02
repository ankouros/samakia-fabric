# Consumer Onboarding

This guide explains how a platform declares intent to consume Samakia Fabric.

See `catalog.md` and `quickstart.md` for guided flows.

1) Choose a consumer type and variant:
- `ready` (default): no service deployed; substrate only.
- `enabled` (opt-in): service exists; contract enforcement applies.

2) Select the appropriate contract manifest:
- `contracts/consumers/<type>/<variant>.yml`

3) Run the Phase 6 entry check:
```bash
make phase6.entry.check
```

4) Use the acceptance plan:
- `acceptance/PHASE6_ACCEPTANCE_PLAN.md`

No service deployment is performed by Phase 6.

## Tenant drift visibility (Phase 12 Part 5)

Tenants receive read-only drift summaries under:

- `artifacts/tenant-status/<tenant>/drift-summary.*`

These summaries are signals only; remediation remains operator-controlled.

## Proposal flow for binding changes (Phase 12 Part 4)

Binding changes may be submitted via the proposal workflow for operator review and approval.
See the operator cookbook for the canonical commands:

- `docs/operator/cookbook.md` (Tenant proposals section)
