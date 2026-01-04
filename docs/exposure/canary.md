# Canary Exposure (Phase 17 Step 4)

This file documents the real canary exposure choreography and the required
runner prerequisites. It is intentionally narrow in scope and secrets-safe.

## Canary selection

- ENV: samakia-dev
- TENANT: canary
- WORKLOAD: sample
- Provider: postgres
- Variant: single

Rationale: minimal blast radius with a single database consumer and a
low-risk canary tenant/workload.

## Runner prerequisites (secrets-safe)

Live verification requires a seeded secrets backend and resolvable canary
endpoint. Secrets remain local and are never committed. Vault is the default
backend; ensure the runner has:
- `VAULT_ADDR` and `VAULT_TOKEN` configured
- `~/.config/samakia-fabric/pki/shared-bootstrap-ca.crt` for Vault TLS

Connectivity requirements:
- `db.canary.internal` must resolve on the runner (CNAME to `db.internal.shared`).
- `db.internal.shared` must resolve to HAProxy nodes on the shared VLAN.
- TCP 5432 reachable with TLS required; HAProxy is TCP passthrough and Postgres
  terminates TLS. CA comes from the internal Postgres PKI (default:
  `~/.config/samakia-fabric/pki/postgres-internal-ca.crt`).

## Latest execution (2026-01-04)

Sequence:
- Plan: `evidence/exposure-plan/canary/sample/2026-01-03T19:44:28Z`
- Approve: `evidence/exposure-approve/canary/sample/2026-01-03T19:44:34Z`
- Apply: `evidence/exposure-apply/canary/sample/2026-01-03T19:44:40Z`
- Verify (live): `evidence/exposure-verify/canary/sample/2026-01-04T02:13:42Z` (PASS)

Blocker:
- None (latest live verify succeeded).

Next steps:
- Rerun the full plan/approve/apply/verify/rollback sequence when needed for
  Phase 17 Step 4 completion evidence.
