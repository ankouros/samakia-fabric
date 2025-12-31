# Tenant onboarding (design-only)

This phase defines how to onboard a **tenant = project** using contract files.
No infrastructure is provisioned in Phase 10.

## Steps

1. Copy templates from `contracts/tenants/_templates/`.
2. Fill out:
   - `tenant.yml`
   - `policies.yml`
   - `quotas.yml`
   - `endpoints.yml` (metadata only; secrets are references)
   - `networks.yml`
   - `consumers/*/ready.yml`
3. Validate:

```
make tenants.validate
```

4. Track governance gates:

```
make phase10.entry.check
```

## Related

- `docs/tenants/policies-and-quotas.md`
- `docs/tenants/consumer-bindings.md`
- `docs/consumers/quickstart.md`
- `docs/operator/cookbook.md`
