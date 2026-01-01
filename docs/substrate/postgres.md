# Postgres Executor (Design-Only)

Design notes:
- Consumer: `database`
- Provider: `postgres`
- Variants: `single` and `cluster`

Contracts:
- `contracts/tenants/**/consumers/database/enabled.yml`

Expectations:
- `ha_ready: true`
- DR testcases must reference `contracts/substrate/dr-testcases.yml`
- Secret material is referenced by `secret_ref` only
