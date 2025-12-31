# AI Runbook — Incident Triage (Read-Only)

## Preconditions
- Phase acceptance markers exist (Phase 0–6).
- REQUIRED-FIXES.md has no OPEN blockers for the scope.
- Operator confirms this is a read-only triage.

## Commands
- `make policy.check`
- `ENV=samakia-prod make minio.quorum.guard`
- `make phase2.accept`
- `rg -n "ERROR|FAIL" evidence/ audit/ || true`

## Decision Points
- IF any acceptance gate fails → stop and record in REQUIRED-FIXES.md.
- IF quorum guard is WARN/FAIL → do not proceed with any state migration.
- IF DNS/MinIO acceptance fails → escalate to operator.

## Refusal Conditions
- Missing acceptance markers.
- Any request to run Terraform apply or Ansible apply.
- Any request to bypass TLS or policy gates.

## Evidence Artifacts
- `audit/minio-quorum-guard/<UTC>/report.md`
- `evidence/drift/<env>/<UTC>/` (if drift packet run separately)

## Exit Criteria
- Read-only evidence collected.
- PASS/FAIL status documented.
- No infrastructure changes made.
