# Tenants (Project Binding)

Samakia Fabric treats each tenant as a **project**: a stateless compute domain
that consumes stateful substrate services (DB/MQ/Cache/Vector) via contracts.

This directory documents the **design-only** Phase 10 model and how to
author tenant contracts safely.
Phase 10 Part 2 adds **guarded execute mode** for enabled bindings and
Vault-first credentials issuance (file backend by explicit exception).

## Docs

- `docs/tenants/onboarding.md`
- `docs/tenants/isolation-model.md`
- `docs/tenants/policies-and-quotas.md`
- `docs/tenants/credentials-and-endpoints.md`
- `docs/tenants/consumer-bindings.md`
- `docs/tenants/selfservice.md`

Related:

- `docs/consumers/catalog.md`
- `docs/operator/cookbook.md`
