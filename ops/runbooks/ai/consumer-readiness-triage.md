# AI Runbook — Consumer Readiness Triage (Read-Only)

## Preconditions
- Phase 6 acceptance markers exist.
- Consumer contracts present under `contracts/consumers/`.

## Commands
- `make consumers.validate`
- `make consumers.ha.check`
- `make consumers.disaster.check`
- `make consumers.evidence`

## Decision Points
- IF any contract validation fails → stop and record failure.
- IF HA readiness fails → do not proceed with consumer onboarding.

## Refusal Conditions
- Any request to deploy consumer services.
- Any request to bypass HA readiness checks.

## Evidence Artifacts
- `evidence/consumers/<type>/<variant>/<UTC>/`

## Exit Criteria
- Readiness evidence packet produced.
- PASS/FAIL summary documented.
