# Phase 14 Acceptance Plan (Design)

Phase 14 defines runtime operations, SLO ownership, and signal classification.
Acceptance is design-only and uses synthetic inputs only.

## A) Contract validation (CI-safe)

Required:
- Validate SLO contracts against `contracts/slo/slo.schema.json`.
- Validate runtime observation contract against `contracts/runtime-observation/observation.schema.json`.

PASS criteria:
- Schema validation succeeds.
- Contracts contain no secrets.

## B) Synthetic signal classification (CI-safe)

Required:
- Generate synthetic drift and SLO metrics inputs.
- Classify each signal deterministically (Infra Fault, Drift, SLO Violation, OK).
- Produce example evidence packets under `evidence/runtime/`.

PASS criteria:
- Deterministic classification is recorded.
- Evidence packets include manifests and no secrets.

## C) Operator UX verification

Required:
- Operator docs describe signal taxonomy, incident lifecycle, and SLO ownership.
- Evidence layout is documented.

PASS criteria:
- Docs exist and match the contracts.
- No remediation or auto-execution steps are described.

## Evidence requirements

- Evidence is redacted and deterministic.
- No live systems are touched during acceptance.
