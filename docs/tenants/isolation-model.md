# Isolation model

Tenants are isolated by contract. Isolation level declares expected separation
and is validated by policy (not provisioned in Phase 10).

## Levels

- **soft**: logical separation only.
- **strong**: network + policy separation; shared infra allowed.
- **hard**: strict boundaries; cross-tenant access must be false.

Isolation is declared in `contracts/tenants/*/tenant.yml`:

```
"isolation": {"level": "soft|strong|hard"}
```

Related:

- `docs/tenants/policies-and-quotas.md`
- `docs/tenants/consumer-bindings.md`
