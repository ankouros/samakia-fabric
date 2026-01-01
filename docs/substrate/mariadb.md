# MariaDB Executor (Design-Only)

Design notes:
- Consumer: `database`
- Provider: `mariadb`
- Variants: `single` and `cluster`

Contracts:
- `contracts/tenants/**/consumers/database/enabled.yml`

Expectations:
- `ha_ready: true`
- DR testcases reference `contracts/substrate/dr-testcases.yml`
- Secrets use `secret_ref` only
