# Shared Observability Policy

Shared observability is a platform-critical control plane.
It is treated as a Tier-1 workload with strict HA requirements.

## Contract

The authoritative policy is:

- `contracts/observability/policy.yml`

The policy is enforced by:

- `ops/observability/validate/validate-policy.sh`
- `ops/observability/validate/validate-replicas.sh`
- `ops/observability/validate/validate-affinity.sh`

## Invariants (non-negotiable)

- replicas >= 2
- anti-affinity required (no single-node placement)
- at least two distinct hosts
- scope: Prometheus, Alertmanager, Grafana, Loki

## Enforcement

Violations:

- FAIL CI
- FAIL acceptance
- FAIL operator apply

No warnings or best-effort paths are allowed.

## Remediation

If the policy fails:

1) Restore at least two `obs-*` nodes in `fabric-core/terraform/envs/samakia-shared`.
2) Ensure `target_node` placements are distinct.
3) Re-run `make shared.obs.policy ENV=samakia-shared`.
