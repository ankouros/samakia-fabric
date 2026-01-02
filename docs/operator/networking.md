# Networking Determinism Policy

Stable IP assignments are required for tier-0 services. Containers may be
replaced, but their network identity must remain deterministic.

## Tiered policy

### Tier 0 (critical control-plane)

- DNS, MinIO, shared control-plane services, observability
- MAC address must be pinned in Terraform
- DHCP reservations must be configured for pinned MACs

### Tier 1 (important services)

- Prefer pinned MACs when possible
- If DHCP is used, document a cutover plan before replacement

### Tier 2 (non-critical)

- Replacement may change IP
- Document a safe replace and cutover plan

## Cutover checklist (IP change expected)

1. Plan downtime or blue/green strategy.
2. Update DNS or service discovery targets.
3. Rotate SSH known_hosts entries.
4. Update any monitoring targets or allowlists.
5. Re-run acceptance for affected services.

## Notes

- MAC pinning is enforced in Terraform for tier-0 services.
- DHCP reservations are an operator responsibility.
