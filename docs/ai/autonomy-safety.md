# Autonomy Safety Envelope (Design Only)

Autonomy is **opt-in, scoped, and revocable**. This document defines the safety
controls required before any conditional autonomy could be considered.

## Global kill switch

- `AI_AUTONOMY_DISABLE=1` disables all autonomy evaluation and execution paths.
- The switch must be checked before any autonomy action is considered.

## Per-action kill switch

- Each action has an explicit `action_id` and a dedicated disable flag:
  - `AI_AUTONOMY_DISABLE_ACTION_<ACTION_ID>=1`
- Per-action switches override global allowlists.

## Escalation paths

- Any autonomy action escalates to the operator on failure.
- Escalation must include evidence references and rollback instructions.
- Operator always retains final control.

## Monitoring for misuse

- All autonomy decisions emit audit evidence.
- Repeated failures or unexpected triggers emit alerting events.
- Actions are rate-limited per `max_frequency`.

## Automatic freeze conditions

- Any policy violation or unexpected scope expansion.
- More than one failure in a 24-hour window per action.
- Evidence integrity check failure.
- Manual operator freeze.

Autonomy remains a **design artifact** until a future phase explicitly enables
execution with approval and acceptance gates.
