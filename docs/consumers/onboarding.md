# Consumer Onboarding

This guide explains how a platform declares intent to consume Samakia Fabric.

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
