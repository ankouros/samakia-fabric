# Consumer bindings

A tenant declares **ready** bindings per consumer type. Enabled bindings
are deferred to later phases.

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
