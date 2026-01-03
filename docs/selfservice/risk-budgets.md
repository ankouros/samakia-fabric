# Self-Service Risk Budgets (Phase 15 Part 3 — Design)

Risk budgets are design-only controls that bound self-service autonomy.
They are **advisory only** in Phase 15 Part 3.

## Dimensions

- **Proposal frequency**: number of proposals per window.
- **Change magnitude**: capacity delta, exposure scope size.
- **Incident count**: recent incident frequency/severity.
- **SLO violations**: recent error budget breaches.
- **Drift stability**: time since last drift event.

## Budget consumption (design)

- Each proposal consumes a portion of the budget based on magnitude.
- Budgets reset on a fixed cadence (e.g., monthly) or after stability windows.
- Large changes consume budgets faster than small changes.

## Budget exhaustion behavior (design)

- Proposals are still accepted.
- Approvals require a senior operator.
- Autonomy levels freeze at Level 0.

## Statement

Risk budgets are advisory only at this stage. No automation is introduced.
