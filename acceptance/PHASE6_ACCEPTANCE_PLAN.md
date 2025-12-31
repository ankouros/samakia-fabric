# Phase 6 Acceptance Plan (Design Only)

Phase 6 defines contracts and acceptance patterns. It does **not** deploy
consumer services.

## Objectives
- Validate contract schema and manifests (ready/enabled variants).
- Validate evidence packet expectations are present.
- Validate disaster/recovery expectations are declared.
- Validate HA-ready defaults and override guardrails.

## Read-only checks
- Schema validation for all consumer contracts.
- Contract lint: required fields, enums, and invariants.
- Evidence packet references are present and valid.

## Safe simulation mapping
- Disaster scenarios map to Phase 3 GameDays (read-only evidence snapshots).
- No destructive actions are executed in Phase 6.

## Evidence packets (Phase 4)
- Substrate drift packet
- Consumer readiness packet
- Compliance packet (when enabled variant is used)
- Release readiness packet (when promotion is intended)

## PASS/FAIL semantics
- PASS: all contracts validated and evidence requirements declared.
- FAIL: missing contracts, missing schema, or invalid fields.
