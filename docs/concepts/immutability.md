# Immutability in Samakia Fabric

This document defines **immutability as an operational principle**
within Samakia Fabric.

Immutability is not an absolute rule.
It is a **default posture** with clearly defined boundaries.

---

## 1. What Immutability Means Here

In Samakia Fabric, immutability means:

> Systems are replaced, not repaired.

A running system is not treated as a long-lived artifact.
It is treated as an **instance of declared intent**.

---

## 2. Why Immutability Matters

Immutability is adopted to:

- Reduce configuration drift
- Minimize operational entropy
- Improve recovery speed
- Enable reproducible environments
- Make automation and AI safer

Manual repair introduces hidden state.
Immutability removes it.

---

## 3. Scope of Immutability

### Immutable by Design

The following are treated as immutable:

- LXC containers (as instances)
- Golden images
- Terraform-managed infrastructure resources
- LXC feature flags
- Network and storage attachments

If these break, they are replaced.

---

### Mutable by Necessity

The following are allowed to change in place:

- Runtime application data
- Logs
- External storage volumes
- Temporary debug state (during incident response)

These must not affect system identity.

---

## 4. Immutability Across Layers

### 4.1 Packer (Images)

- Images are immutable artifacts
- Changes require a new image version
- Old images are retained for rollback

Images are never modified in place.

---

### 4.2 Terraform (Infrastructure)

- Terraform expresses desired state
- Immutable attributes cause destroy/recreate
- Drift is resolved via re-apply or rebuild

Terraform does not “patch” resources.

---

### 4.3 Ansible (Configuration)

- Ansible enforces desired policy
- It is idempotent, not immutable
- It supports reconciliation, not mutation of identity

Ansible should not introduce hidden state.

---

## 5. Containers as Cattle

Samakia Fabric adopts the **cattle model**:

- Containers are disposable
- Identity comes from code, not the instance
- Failure leads to replacement

Manual fixes are temporary and discouraged.

---

## 6. Rebuild Over Repair

Preferred recovery sequence:

1. Identify failure
2. Destroy affected container
3. Recreate via Terraform
4. Reapply Ansible configuration

This sequence is faster and safer than manual repair.

---

## 7. Allowed Exceptions

Immutability may be temporarily relaxed for:

- Emergency debugging
- Incident mitigation
- Data extraction

Rules for exceptions:
- Must be time-bound
- Must be documented
- Must be reconciled back into code

Permanent exceptions are not allowed.

---

## 8. Anti-Patterns (Explicitly Rejected)

- SSH-ing into containers for permanent fixes
- Hot-patching golden images
- Editing Terraform-managed resources manually
- Treating containers as pets

These lead to drift and operational fragility.

---

## 9. Immutability and GitOps

Immutability enables GitOps by ensuring:

- Git reflects desired state
- Reality can be replaced to match Git
- Drift has a deterministic resolution

Without immutability, GitOps degenerates into documentation.

---

## 10. Immutability and Security

Immutability improves security by:

- Limiting attacker persistence
- Simplifying incident response
- Reducing privilege escalation windows

A compromised container is destroyed, not cleaned.

---

## 11. Immutability and AI Agents

Immutability makes AI-assisted operations safer:

- Actions are predictable
- Rollback is simple
- Side effects are minimized

AI agents should prefer replacement over modification.

---

## 12. Summary

In Samakia Fabric:

- Immutability is the default
- Rebuild is preferred over repair
- Exceptions are rare and controlled
- Drift is a failure mode, not a feature

If a system cannot be safely rebuilt,
it does not belong in the platform.
