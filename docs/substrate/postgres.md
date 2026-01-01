# Postgres Executor (Plan + DR Dry-Run)

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

Operator commands: `docs/operator/cookbook.md` (substrate plan + DR dry-run).

## Capacity & noisy-neighbor guardrails

Capacity is enforced via tenant `capacity.yml` contracts. The guard evaluates
declared intent and blocks apply/DR execute when limits are exceeded. Evidence
is written under `evidence/tenants/<tenant>/<UTC>/substrate-capacity/`.
