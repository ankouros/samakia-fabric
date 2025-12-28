# System Lifecycle in Samakia Fabric

This document defines the **end-to-end lifecycle** of systems managed by
Samakia Fabric.

Lifecycle clarity is essential for:
- Predictability
- Automation safety
- Operational confidence

---

## 1. Lifecycle Philosophy

Samakia Fabric follows a **declare → build → operate → replace** lifecycle.

Systems are not “maintained forever”.
They are **intentionally transient**.

---

## 2. Lifecycle Stages Overview

The standard lifecycle consists of:

1. Design
2. Image Build
3. Provisioning
4. Configuration
5. Operation
6. Replacement
7. Decommissioning

Each stage has a clear owner and tool.

---

## 3. Design Stage

### Purpose

- Define intent
- Make trade-offs explicit
- Avoid accidental complexity

### Artifacts

- Architecture documents
- Terraform module definitions
- Image requirements
- Security constraints

No infrastructure is created here.

---

## 4. Image Build Stage (Packer)

### Responsibilities

- Build immutable golden images
- Apply OS-level hardening
- Prepare runtime prerequisites

### Rules

- Images are versioned
- Images are never modified after build
- Rebuilds create new versions

Images define the baseline identity.

---

## 5. Provisioning Stage (Terraform)

### Responsibilities

- Declare infrastructure resources
- Attach networks and storage
- Define placement and lifecycle rules

### Rules

- Terraform is the source of truth
- Manual changes are forbidden
- Drift is resolved by replacement

Terraform controls existence, not behavior.

---

## 6. Configuration Stage (Ansible)

### Responsibilities

- Enforce configuration policy
- Apply security baselines
- Prepare platforms for workloads

### Rules

- Idempotent execution only
- No identity mutation
- No hidden state

Ansible converges systems to policy.

---

## 7. Operation Stage

### Characteristics

- Systems run unattended
- Observability detects issues
- Automation handles routine actions

Manual intervention is exceptional.

---

## 8. Change Management

### Allowed Changes

- New image versions
- Terraform plan/apply
- Ansible policy updates

### Forbidden Changes

- Manual hotfixes
- In-place identity changes
- Snowflake modifications

Change flows through code.

---

## 9. Replacement Stage

Replacement is preferred over repair.

Triggers include:
- Image updates
- Security incidents
- Configuration drift
- Infrastructure changes

Replacement is deterministic and fast.

---

## 10. Decommissioning Stage

### Responsibilities

- Destroy unused resources
- Clean Terraform state
- Reclaim capacity

### Rules

- Decommission is intentional
- Orphans are failures
- State must remain clean

Dead resources are liabilities.

---

## 11. Failure Handling in the Lifecycle

Failures are expected.

Standard response:
1. Detect failure
2. Decide rebuild vs repair
3. Replace if uncertain
4. Document outcome

Ambiguity favors replacement.

---

## 12. Lifecycle and HA

- HA reduces impact during replacement
- Replacement restores correctness
- Lifecycle design assumes failure

HA without lifecycle discipline fails.

---

## 13. Lifecycle and Security

- Compromised systems are destroyed
- Credentials are rotated via rebuild
- Forensics may precede replacement

Cleaning is never sufficient.

---

## 14. Lifecycle and GitOps

Git is the lifecycle authority.

- Desired state in Git
- Actual state is disposable
- Drift is reconciled by rebuild

Git is not documentation — it is control.

---

## 15. Lifecycle Anti-Patterns

- Long-lived mutable servers
- Manual patching
- “Just this once” fixes
- Undocumented exceptions

These break the lifecycle model.

---

## 16. Summary

In Samakia Fabric:

- Systems are born from code
- They live predictably
- They are replaced intentionally
- They die cleanly

If a system cannot be safely destroyed
and recreated, it is incorrectly designed.
