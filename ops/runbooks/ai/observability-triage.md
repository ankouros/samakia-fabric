# AI Runbook — Observability Triage (Read-Only)

## Preconditions
- Shared observability plane deployed and accepted.
- VIP endpoints reachable from runner.

## Commands
- `ENV=samakia-shared make shared.obs.accept`
- `ENV=samakia-shared make shared.obs.ingest.accept`
- `curl -fsS https://192.168.11.122:9090/-/ready` (strict TLS)

## Decision Points
- IF Grafana returns 503/5xx → stop and record in REQUIRED-FIXES.md.
- IF Loki ingestion check fails → stop; no remediation without approval.

## Refusal Conditions
- Any request to restart services or apply Ansible.
- Any request to disable TLS verification.

## Evidence Artifacts
- `audit/shared-obs-ingest/<UTC>/` (if applicable)

## Exit Criteria
- Observability acceptance PASS/FAIL recorded.
- No runtime mutations.
