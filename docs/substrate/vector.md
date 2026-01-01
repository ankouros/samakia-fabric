# Vector Executor (Qdrant, Plan + DR Dry-Run)

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

Operator commands: `docs/operator/cookbook.md` (substrate plan + DR dry-run).
