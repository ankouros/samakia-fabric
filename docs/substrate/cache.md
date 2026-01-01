# Cache Executor (Dragonfly, Design-Only)

Design notes:
- Consumer: `cache`
- Provider: `dragonfly` (fixed)
- Variants: `single` and `cluster`

Contracts:
- `contracts/tenants/**/consumers/cache/enabled.yml`

Expectations:
- `ha_ready: true`
- DR testcases reference `contracts/substrate/dr-testcases.yml`
- Secrets use `secret_ref` only

Redis is not supported as an executor. Client compatibility is via Dragonfly's Redis protocol.
