# Cache Consumer

Variants:
- `ready`: substrate pattern only; no cluster deployed.
- `enabled`: cache cluster exists externally; Fabric enforces contract.

Contracts:
- `contracts/consumers/cache/ready.yml`
- `contracts/consumers/cache/enabled.yml`

Acceptance (design-only in Phase 6):
- endpoint readiness checks
- anti-affinity checks
- evidence packet references
