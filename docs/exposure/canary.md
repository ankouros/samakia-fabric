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

## Prerequisites for Phase 17 Step 4 (Live Verify)

- Vault reachable from the runner (shared VLAN runner or SSH port-forward).
- Secret `secret/tenants/canary/database/sample` exists (KV mount `secret/`).
- `username` and `password` fields are non-empty.
- Database endpoint resolves and accepts TLS.

## Runner prerequisites (secrets-safe)

Live verification requires a seeded secrets backend and resolvable canary
endpoint. Secrets remain local and are never committed. Vault is the default
backend; ensure the runner has:
- `VAULT_ADDR` and `VAULT_TOKEN` configured
- `~/.config/samakia-fabric/pki/shared-bootstrap-ca.crt` for Vault TLS
- `ops/ca/postgres-internal-ca.crt` available (can be a runner-local symlink to
  `~/.config/samakia-fabric/pki/postgres-internal-ca.crt`) so `ca_ref` lookups
  succeed during TLS verification

Connectivity requirements:
- `db.canary.internal` must resolve on the runner (CNAME to `db.internal.shared`).
- `db.internal.shared` must resolve to HAProxy nodes on the shared VLAN.
- Runner must route to VLAN120 (shared plane) via the shared edge gateway.
- TCP 5432 reachable with TLS required; HAProxy is TCP passthrough and Postgres
  terminates TLS. CA comes from the internal Postgres PKI (default:
  `~/.config/samakia-fabric/pki/postgres-internal-ca.crt`).

## Latest execution (2026-01-04)

Sequence:
- Plan: `evidence/exposure-plan/canary/sample/2026-01-04T04:30:25Z`
- Approve: `evidence/exposure-approve/canary/sample/2026-01-04T04:30:32Z`
- Apply: `evidence/exposure-apply/canary/sample/2026-01-04T04:30:47Z`
- Verify (live): `evidence/exposure-verify/canary/sample/2026-01-04T04:39:05Z`
- Rollback: `evidence/exposure-rollback/canary/sample/2026-01-04T04:39:19Z`
- Consolidated evidence: `evidence/exposure-canary/canary/sample/2026-01-04T04:40:26Z`

Outcome:
- Live verify succeeded and rollback returned to baseline.

Notes:
- Canary secret `ca_ref` must point to `postgres-internal-ca.crt` so TLS
  verification succeeds against the internal Postgres PKI.
- Canary DB user and database must exist with credentials that match the
  canary secret before live verify runs.
