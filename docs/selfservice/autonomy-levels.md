# Self-Service Autonomy Levels (Phase 15 Part 3 — Design)

This document defines bounded autonomy levels for self-service. **Only Level 0
is implemented today.** Levels 1–3 are design-only and require future acceptance
markers before any tooling changes.

## Level 0 — Propose Only (Default, Implemented)

- Tenants can submit proposals.
- Tenants can run validation/plan previews.
- Operators review, approve, and execute.
- No tenant execution rights.

## Level 1 — Assisted Propose (Design Only)

- Tenants may request pre-approved templates.
- Operators still approve every change.
- No execution rights granted.

## Level 2 — Conditional Progression (Design Only)

Certain low-risk changes **may** be auto-approved, only if:
- Risk budget is unused.
- SLOs are stable.
- No recent incidents.

Execution remains **operator-run**.

## Level 3 — Autonomous (Explicitly Out of Scope)

- Self-apply, self-heal, auto-scale.
- Not allowed in Samakia Fabric today.

## Statement

Only **Level 0** is implemented. Levels 1–3 are design-only and locked behind
future acceptance gates.
