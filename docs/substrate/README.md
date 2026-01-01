# Substrate Executors (Design-Only)

This directory documents tenant-scoped substrate executors for stateful primitives.

Scope:
- Contract-first design for `enabled.yml` bindings
- Read-only planning and DR dry-run (no execute in Part 1)
- Two variants for each consumer: `single` and `cluster`

Reference contracts:
- `contracts/substrate/dr-testcases.yml`
- `contracts/tenants/**/consumers/**/enabled.yml`

See provider-specific notes:
- `docs/substrate/postgres.md`
- `docs/substrate/mariadb.md`
- `docs/substrate/rabbitmq.md`
- `docs/substrate/cache.md`
- `docs/substrate/vector.md`
- `docs/substrate/ha-semantics.md`
- `docs/substrate/dr.md`

Operator commands live in `docs/operator/cookbook.md` (plan + DR dry-run only).
