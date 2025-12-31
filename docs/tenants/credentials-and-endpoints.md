# Credentials and endpoints

Endpoints are **metadata only** in Phase 10. Secrets are not stored in Git.
Use `secret_ref` to reference external secret material. Enabled bindings
may issue credentials **offline-first** with explicit guards.

Production execution requires a change window and evidence signing per
execute policy.

Optional Vault integration is supported when explicitly configured; the
offline file-backed secrets path remains the default.

## Endpoint rules

- Host/port/protocol must be declared
- `tls_required` must be true for stateful services
- `secret_ref` is a string reference, not secret material

Validate endpoints with:

```
make tenants.validate
```

Related:

- `contracts/tenants/_schema/endpoints.schema.json`
- `docs/operator/safety-model.md`
- `docs/operator/cookbook.md`
