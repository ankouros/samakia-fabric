# Vector Executor (Qdrant, Design-Only)

Design notes:
- Consumer: `vector`
- Provider: `qdrant`
- Variants: `single` and `cluster`

Contracts:
- `contracts/tenants/**/consumers/vector/enabled.yml`

Expectations:
- `ha_ready: true`
- DR testcases reference `contracts/substrate/dr-testcases.yml`
- Secrets use `secret_ref` only
