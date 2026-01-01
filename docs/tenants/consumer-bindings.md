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
  - `executor` block (`provider`, `mode`, `plan_only`)
  - `endpoints` (`host`, `port`, `protocol`, `tls_required`)
  - `secret_ref` (reference only)
  - DR expectations (`dr.required_testcases`, `dr.backup`, `dr.restore_verification`)
- Execution is always opt-in and guarded; no apply in CI
- Endpoints are metadata only; no secrets

Validate:

```
make tenants.validate
make tenants.execute.policy.check
make tenants.dr.validate
```
