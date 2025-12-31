# AI Runbook — Drift Triage (Read-Only)

## Preconditions
- Runner env present (`~/.config/samakia-fabric/env.sh`).
- No OPEN items in REQUIRED-FIXES.md.
- This runbook is read-only.

## Commands
- `make policy.check`
- `bash ops/scripts/drift-packet.sh <env> --sample` (offline sample)
- `ENV=<env> make tf.plan` (read-only plan)

## Decision Points
- IF plan shows destroy or drift → document and request operator decision.
- IF plan shows errors → stop and capture evidence only.

## Refusal Conditions
- Any request to run `terraform apply`.
- Any request to disable TLS checks.

## Evidence Artifacts
- `evidence/drift/<env>/<UTC>/`

## Exit Criteria
- Drift evidence packet generated.
- Plan outcome summarized without secrets.
