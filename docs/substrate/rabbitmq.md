# RabbitMQ Executor (Design-Only)

Design notes:
- Consumer: `message-queue`
- Provider: `rabbitmq`
- Variants: `single` and `cluster`

Contracts:
- `contracts/tenants/**/consumers/message-queue/enabled.yml`

Expectations:
- `ha_ready: true`
- DR testcases reference `contracts/substrate/dr-testcases.yml`
- Secrets use `secret_ref` only

Operator commands: `docs/operator/cookbook.md` (substrate plan + DR dry-run).
