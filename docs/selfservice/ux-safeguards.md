# UX Safeguards Against Policy Erosion (Phase 15 Part 4 — Design)

Self-service UX must preserve policy rigor and prevent convenience-driven
risk expansion. This is design-only.

## Why one-click apply is forbidden

- Removes context required for safe approvals.
- Encourages rushed decisions and approval fatigue.
- Violates the operator-controlled execution contract.

## Why approvals require time and context

- Operators must validate scope, policy gates, and evidence.
- Change windows and signatures require deliberate review.

## Why warnings are not softened

- Clarity prevents hidden risk and false confidence.
- Warnings are evidence-based, not negotiable UX hints.

## Why some requests will always be denied

- Secrets access, policy bypass, and auto-approval are out of scope.
- Safety and auditability override convenience.

## UX anti-patterns (do not build)

- “Apply now” or “instant approval” buttons.
- Auto-escalation after repeated submissions.
- Hiding denial reasons to reduce friction.
- Frictionless approval flows that omit context.

## Dangerous UX examples

- Defaulting a proposal to approved status.
- Softening critical warnings with positive language.
- Allowing status changes without evidence links.

## Statement

UX must reinforce guardrails, not pressure operators to relax them.
