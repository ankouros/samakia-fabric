# Samakia Fabric – Core Principles

This document defines the **non-negotiable principles**
that guide the design, operation, and evolution of Samakia Fabric.

If a decision violates these principles,
it is considered incorrect — even if it “works”.

---

## 1. Infrastructure Is Code

All infrastructure must be:

- Declarative
- Versioned
- Reviewable
- Reproducible

Manual changes are operational debt.

If it cannot be expressed as code,
it does not belong in the platform.

---

## 2. Replace Over Repair

Systems are replaced, not repaired.

- Failure triggers rebuild
- Drift triggers replacement
- Compromise triggers destruction

Repair is a temporary diagnostic step, not a solution.

---

## 3. Immutability by Default

Immutability is the default posture.

- Images are immutable
- Infrastructure identity is immutable
- Runtime mutation is minimized

Exceptions must be explicit, documented, and temporary.

---

## 4. Clear Responsibility Boundaries

Responsibilities are explicitly separated:

- Fabric provides IaaS
- Platforms provide PaaS
- Applications own business logic

Blurring boundaries causes outages.

---

## 5. Simplicity Over Cleverness

Simple systems fail predictably.
Clever systems fail mysteriously.

Samakia Fabric prefers:
- Fewer moving parts
- Explicit behavior
- Boring, proven patterns

Complexity must justify itself.

---

## 6. Determinism Beats Automation

Automation is valuable only if it is deterministic.

- Predictable outcomes > autonomous behavior
- Explicit workflows > magic healing
- Human override must always be possible

Automation without determinism is dangerous.

---

## 7. Failure Is Expected

Failures are normal.

The platform is designed to:
- Detect failure quickly
- Limit blast radius
- Recover deterministically

Designing for success alone is a failure.

---

## 8. Observability Is Mandatory

If it cannot be observed, it cannot be trusted.

Every critical system must provide:
- Clear signals
- Actionable alerts
- Contextual visibility

Silence is not stability.

---

## 9. Security Is a Design Property

Security is not a feature added later.

Samakia Fabric assumes:
- Breach is possible
- Credentials will leak
- Systems will be compromised

Containment and recovery are mandatory.

---

## 10. Git Is the Source of Truth

Git defines desired state.

- Reality may drift
- Git does not

Recovery always flows from Git to reality,
never the reverse.

---

## 11. Humans Remain in Control

Automation assists humans.
It does not replace judgment.

- Humans approve destruction
- Humans define intent
- Humans own consequences

There is always a human in the loop.

---

## 12. Explicit Over Implicit

Implicit behavior is forbidden.

- Defaults must be visible
- Assumptions must be stated
- Side effects must be documented

If it is surprising, it is wrong.

---

## 13. Reproducibility Over Convenience

Convenience creates shortcuts.
Shortcuts create drift.

Samakia Fabric prefers:
- Rebuildable systems
- Documented workflows
- Repeatable outcomes

Speed without repeatability is fragile.

---

## 14. Documentation Is Part of the System

Documentation is not optional.

If it is not documented:
- It is not supported
- It is not stable
- It is not trusted

Code explains *how*.
Documentation explains *why*.

---

## 15. The Platform Must Be Explainable

Every design decision must be explainable:

- To a new engineer
- To an auditor
- To an AI agent

If it cannot be explained simply,
it is too complex.

---

## 16. Final Rule

When in doubt:

- Prefer destruction over mutation
- Prefer rebuild over repair
- Prefer clarity over speed
- Prefer boring over clever

If a system cannot survive being destroyed,
it does not belong in Samakia Fabric.
