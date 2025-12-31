# Consumer bindings

A tenant declares **ready** bindings per consumer type. **Enabled** bindings
are supported in Phase 10 Part 2 with explicit guards and no automatic apply.

## Ready bindings

- File: `consumers/<type>/ready.yml`
- Must be HA-ready (`ha_ready: true`)
- Must include disaster testcases (`dr_testcases`)

Validate:

```
make tenants.validate
```

Related:

- `docs/consumers/catalog.md`
- `docs/consumers/variants.md`
- `docs/operator/cookbook.md`

## Enabled bindings (guarded)

- File: `consumers/<type>/enabled.yml`
- Must include:
  - `mode` (`dry-run` or `execute`)
  - `endpoint_ref` and `secret_ref` (metadata only)
  - DR expectations (`dr_testcases`, `restore_testcases`, `backup_target`)
  - `owner` block (`tenant_id`, `consumer`)
- Execution is always opt-in and guarded; no apply in CI
- `endpoint_ref` must exist in the tenant `endpoints.yml`

Validate:

```
make tenants.validate
make tenants.execute.policy.check
make tenants.dr.validate
```
