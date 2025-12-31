# Database Consumer

Variants:
- `ready`: substrate pattern only; no cluster deployed.
- `enabled`: database cluster exists externally; Fabric enforces contract.

Contracts:
- `contracts/consumers/database/ready.yml`
- `contracts/consumers/database/enabled.yml`

Acceptance (design-only in Phase 6):
- endpoint readiness checks
- replica/anti-affinity checks
- evidence packet references
