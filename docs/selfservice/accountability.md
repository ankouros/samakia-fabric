# Self-Service Accountability Model (Phase 15 Part 3 — Design)

Autonomy never removes accountability. This document defines attribution and
review responsibilities for self-service workflows.

## Accountability boundaries

- **Tenants** are accountable for proposal intent, accuracy, and justification.
- **Operators** are accountable for approvals, delegations, and execution.
- **Platform owners** are accountable for guardrail definitions and policy gates.

## Attribution rules

- Every proposal, approval, and delegation includes identity fields.
- Evidence packets must link to the responsible actor.
- Prod approvals require signed artifacts.

## Evidence retention

- Evidence is retained per the audit model (see `docs/selfservice/audit-model.md`).
- Legal hold overrides standard retention.

## Post-incident review

- Review both tenant intent and operator decisions.
- Confirm guardrails were applied and evidence is intact.
- Record corrective actions in governance docs.

## Statement

Autonomy never removes accountability.
