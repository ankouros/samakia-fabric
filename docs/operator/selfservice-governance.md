# Self-Service Governance (Phase 15 Part 3 — Design)

This document guides operators on **bounded autonomy** decisions for
self-service proposals. It is design-only; no automation is introduced.

## How to reason about autonomy levels

- Default to **Level 0 (Propose Only)**.
- Higher levels are design-only and require explicit acceptance gates.
- Use risk budgets and stop rules to decide when to pause autonomy.

## Approving with constraints

- Keep scope narrow and time-bound.
- Require change windows and signatures for prod.
- Enforce provider and variant allowlists.

## Reducing or revoking autonomy

- Reduce autonomy immediately on SLO violations or incidents.
- Record the reason and evidence link.
- Require explicit approval to restore autonomy.

## Common failure patterns

- Proposals with unclear or oversized deltas.
- Repeated requests after failed validation.
- Attempts to bypass change windows or policy checks.

## Why "no" is sometimes correct

- Preserves system safety and auditability.
- Prevents hidden blast radius expansion.
- Maintains operator accountability.

See also:
- `docs/selfservice/autonomy-levels.md`
- `docs/selfservice/risk-budgets.md`
- `docs/selfservice/stop-rules.md`
- `docs/selfservice/accountability.md`
