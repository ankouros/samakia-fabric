# Policies and quotas

Policies define **what a tenant is allowed to consume**. Quotas set the
bounds for each consumer type. This is contract-only in Phase 10.

## Policies

- `allowed_consumers`: which consumer types are permitted
- `allowed_variants`: single vs cluster per consumer
- `security_profile`: baseline or hardened
- prod requirements and execution guards

## Quotas

- Per-consumer instance/cluster limits
- Must align with `allowed_consumers`

Validate:

```
make tenants.validate
```

Related:

- `contracts/tenants/_schema/policies.schema.json`
- `contracts/tenants/_schema/quotas.schema.json`
