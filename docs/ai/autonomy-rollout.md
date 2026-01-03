# Autonomy Rollout Model (Design Only)

This document defines staged rollout for conditional autonomy. Each stage must
be reversible with explicit exit criteria.

## Stage 1: Shadow mode

- AI suggests actions; humans execute manually.
- Evidence is captured for every suggestion.

Entry criteria:
- Action contract approved.
- Kill switches documented and tested.
- Operator runbook in place.

Exit criteria:
- 30 days without policy violations.
- Operator review confirms usefulness.

Rollback:
- Disable action via per-action kill switch.

## Stage 2: Assisted mode

- AI prepares action and evidence bundle.
- Human confirmation required for execution.

Entry criteria:
- Shadow mode exit criteria met.
- Rollback procedure validated.
- Audit evidence review completed.

Exit criteria:
- 60 days without policy violations.
- Operator sign-off on action accuracy.

Rollback:
- Global kill switch or revert to shadow mode.

## Stage 3: Conditional autonomy

- AI executes only allowlisted actions under strict guards.
- Human override is always available.

Entry criteria:
- Assisted mode exit criteria met.
- Explicit leadership approval.
- Change window and signing requirements defined.

Exit criteria:
- Any violation triggers immediate rollback.
- Quarterly governance review required.

Rollback:
- Global kill switch + per-action kill switch.
