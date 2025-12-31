# Tenant onboarding (design-only)

This phase defines how to onboard a **tenant = project** using contract files.
No infrastructure is provisioned in Phase 10.

## Steps

Follow the canonical operator cookbook tasks:

- “Create a new tenant from templates”
- “Validate tenant contracts”
- “Generate tenant evidence packet”
- “Phase 10 entry checklist (design-only)”
- “Phase 10 Part 2 entry checklist” and “Phase 10 Part 2 acceptance”

Phase 10 Part 2 adds **guarded execute mode** for enabled bindings and
credential issuance. These remain opt-in and offline-first.

Phase 10 Part 2 acceptance is documented in the operator cookbook.

All commands and guardrails live in:

- `docs/operator/cookbook.md`

## Related

- `docs/tenants/policies-and-quotas.md`
- `docs/tenants/consumer-bindings.md`
- `docs/consumers/quickstart.md`
- `docs/operator/cookbook.md`
