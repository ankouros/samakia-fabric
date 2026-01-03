# Self-Service Stop Rules (Phase 15 Part 3 — Design)

Stop rules are hard kill switches that **freeze self-service autonomy**.
They override all autonomy levels and require explicit operator clearance.

## Stop conditions (examples)

- Critical SLO violation or sustained error budget burn.
- Repeated infra faults in the same window.
- Policy violation attempt or guardrail bypass attempt.
- Breach of risk budget thresholds.
- Manual operator freeze.

## Trigger authority (design)

- Operators may trigger stops at any time.
- Automated triggers are **not implemented**.

## Recording a stop

- Record the trigger in evidence with timestamp, reason, and operator identity.
- Link to incident references and SLO evidence where applicable.

## Lifting a stop

- Requires explicit operator approval.
- Must include a remediation summary and evidence references.

## Statement

Stop rules override all autonomy levels. No automation is introduced.
