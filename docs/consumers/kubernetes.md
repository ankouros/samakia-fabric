# Kubernetes Consumer

Guided flows: `catalog.md` and `quickstart.md`.

Variants:
- `ready`: substrate pattern only; no cluster deployed.
- `enabled`: cluster exists externally; Fabric enforces contract.

Contracts:
- `contracts/consumers/kubernetes/ready.yml`
- `contracts/consumers/kubernetes/enabled.yml`

Acceptance (design-only in Phase 6):
- readiness checks
- HA semantics validation
- evidence packet references
