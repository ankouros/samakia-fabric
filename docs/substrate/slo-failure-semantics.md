# SLO & Failure Semantics (Enabled Contracts)

Enabled consumer contracts must declare explicit service level intent and
failure semantics to avoid ambiguous HA claims.

## Required fields

Each `enabled.yml` must include:

- `slo.tier` (e.g. bronze/silver/gold or tier0/tier1/tier2)
- `failure_semantics.mode`
  - `spof` for `single`
  - `failover` for `cluster`
- `failure_semantics.expectations` (human-readable)
- `dr.rpo_target` and `dr.rto_target` (placeholders accepted)

## Enforcement

The substrate contract validator will fail if:

- Single variant uses a top-tier SLO without override
- Failure semantics are missing or inconsistent
- DR RPO/RTO placeholders are missing

Operator workflows and evidence expectations live in `docs/operator/cookbook.md`.
