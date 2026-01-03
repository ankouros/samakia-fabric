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
backend; this run used an explicit local file backend exception:
- Encrypted secrets file: `~/.config/samakia-fabric/secrets.enc`
- Passphrase file: `~/.config/samakia-fabric/secrets-passphrase`
- Operator input file: `~/.config/samakia-fabric/secrets-input-canary.json`

Note: These files are runner-local, not tracked, and contain no repo data.

Connectivity requirements:
- `db.canary.internal` must resolve on the runner.
- TCP 5432 reachable with TLS required.

## Latest execution (2026-01-03)

Sequence:
- Plan: `evidence/exposure-plan/canary/sample/2026-01-03T19:44:28Z`
- Approve: `evidence/exposure-approve/canary/sample/2026-01-03T19:44:34Z`
- Apply: `evidence/exposure-apply/canary/sample/2026-01-03T19:44:40Z`
- Verify (live): failed (DNS resolution for `db.canary.internal`)
- Rollback: `evidence/exposure-rollback/canary/sample/2026-01-03T19:53:28Z`

Blocker:
- Live verify fails with `tcp connect failed: [Errno -2] Name or service not known`.

Next steps:
- Fix canary DNS resolution for `db.canary.internal` on the runner.
- Rerun verify (live) and then rerun the full plan/approve/apply/verify/rollback
  sequence for final acceptance.
