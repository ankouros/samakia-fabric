# Message Queue Consumer

Variants:
- `ready`: substrate pattern only; no cluster deployed.
- `enabled`: broker cluster exists externally; Fabric enforces contract.

Contracts:
- `contracts/consumers/message-queue/ready.yml`
- `contracts/consumers/message-queue/enabled.yml`

Acceptance (design-only in Phase 6):
- broker readiness checks
- anti-affinity checks
- evidence packet references
