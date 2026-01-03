# Self-Service Guardrail Mapping (Phase 15 Part 3 — Design)

This document maps self-service boundaries to existing phases and guardrails.

## Phase 11 — Substrate executors

- Self-service cannot trigger substrate execution.
- Substrate plan/execute policies remain operator-only.

## Phase 12 — Bindings, secrets, verify

- Self-service proposals can **suggest** binding/capacity changes.
- Secrets materialization/rotation remain operator-controlled.
- Binding verification remains read-only by default.

## Phase 13 — Exposure choreography

- Self-service can request exposure intent only.
- Phase 13 policy evaluation, approvals, and apply are operator-controlled.
- No skipping of plan/approval/verify steps.

## Phase 14 — Runtime signals & SLO

- Runtime evaluation and SLO signals gate autonomy decisions.
- Stop rules can freeze self-service on critical signals.

## Summary

- Self-service is blocked from execution at every phase boundary.
- Guardrails are enforceable and auditable across phases.
