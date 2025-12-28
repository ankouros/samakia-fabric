# High Availability (HA) Design in Samakia Fabric

This document defines **how High Availability (HA) is designed, applied,
and constrained** in Samakia Fabric.

HA is treated as an **engineering trade-off**, not a checkbox.

---

## 1. What HA Means Here

In Samakia Fabric, High Availability means:

> The ability of the platform to continue providing service
> despite the failure of individual components.

HA does NOT mean:
- Zero downtime
- Automatic healing of all failures
- Elimination of operational responsibility

---

## 2. HA Philosophy

Samakia Fabric follows these HA principles:

- Prefer simple, predictable HA over complex automation
- Separate *availability* from *durability*
- Avoid HA at the wrong abstraction layer
- Design for failure, not perfection

False HA is worse than no HA.

---

## 3. Layers of Availability

HA is considered **per layer**, not globally.

| Layer | HA Responsibility |
|----|------------------|
| Hardware | Redundancy, power, networking |
| Proxmox cluster | Node failover, quorum |
| Storage | Data durability & replication |
| Infrastructure | Placement & recovery |
| Workloads | Service-level redundancy |

No single layer provides “full HA”.

---

## 4. Proxmox Cluster HA

### 4.1 Cluster Design

Proxmox provides:
- Cluster membership
- Quorum
- HA groups
- Resource fencing

Samakia Fabric assumes:
- ≥ 3 Proxmox nodes for HA
- Reliable cluster network
- Correct quorum configuration

Without quorum, HA is unsafe.

---

### 4.2 Proxmox HA Manager

Proxmox HA:
- Restarts resources on node failure
- Does NOT guarantee state consistency
- Does NOT protect against application-level failure

HA is best-effort at this layer.

---

## 5. LXC and HA

### 5.1 Containers Are Not HA by Default

LXC containers:
- Run on a single node at a time
- Do not replicate state
- Must be restartable elsewhere

HA for LXC requires **externalization of state**.

---

### 5.2 HA-Compatible Containers

A container is HA-compatible only if:
- It can be destroyed and recreated safely
- It does not contain unique local state
- It relies on external storage or replication

If a container cannot move, it is not HA.

---

## 6. Storage and HA

### 6.1 Storage Is the Hard Part

True HA depends more on storage than compute.

Samakia Fabric distinguishes:
- **Stateless workloads** → easier HA
- **Stateful workloads** → require careful design

---

### 6.2 Supported Storage Models (Conceptually)

- Shared NFS (availability via redundancy)
- Distributed storage (Ceph-ready, future)
- External databases / services

Local-only storage is **not HA-safe**.

---

## 7. Terraform and HA

Terraform is **HA-aware but not HA-enforcing**.

Terraform can:
- Place resources in HA groups
- Declare restart policies
- Express intent

Terraform cannot:
- Guarantee zero downtime
- Repair corrupted state
- Heal application-level failures

HA correctness must be designed, not declared.

---

## 8. Ansible and HA

Ansible supports HA by:
- Enforcing consistent configuration
- Making rebuilds predictable
- Avoiding snowflake nodes

Ansible does NOT:
- Replicate state
- Manage failover logic
- Decide HA topology

---

## 9. HA vs Immutability

HA and immutability are complementary:

- Immutability enables fast replacement
- HA reduces impact during replacement

However:
- HA without immutability increases complexity
- Immutability without HA increases downtime

Samakia Fabric balances both deliberately.

---

## 10. Failure Scenarios

### 10.1 Node Failure

Expected behavior:
- Proxmox detects node failure
- HA manager restarts containers elsewhere (if configured)
- Terraform state remains authoritative
- Operator verifies consistency

HA is not “set and forget”.

---

### 10.2 Storage Failure

Storage failure handling depends on design:
- Shared storage → service interruption possible
- Replicated storage → failover possible
- Local storage → data loss expected

Storage design defines real availability.

---

### 10.3 Application Failure

Application failures are **out of scope** for infra HA.

Mitigation options:
- Application-level redundancy
- Health checks
- External load balancing

Infrastructure HA cannot fix bad applications.

---

## 11. HA Anti-Patterns (Explicitly Rejected)

- Single-node “HA”
- Local-only stateful containers
- HA without quorum
- Mixing HA and manual mutation
- Assuming HA replaces backups

These create false confidence.

---

## 12. HA and GitOps

GitOps strengthens HA by:
- Making recovery deterministic
- Enabling fast redeployments
- Ensuring consistent rebuilds

GitOps does not replace HA mechanisms.
It complements them.

---

## 13. HA and AI Agents

For AI-assisted operations:
- HA decisions must be explicit
- Agents must not assume HA safety
- Replacement is preferred over repair
- State boundaries must be respected

Unsafe HA assumptions are dangerous.

---

## 14. Summary

In Samakia Fabric:

- HA is layered and intentional
- Containers are replaceable, not replicated
- Storage defines availability
- Automation assists but does not guarantee HA
- False HA is actively avoided

If HA cannot be explained clearly,
it is not correctly designed.
