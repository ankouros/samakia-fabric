# IaaS vs PaaS in Samakia Fabric

This document defines **how Infrastructure as a Service (IaaS) and
Platform as a Service (PaaS)** are interpreted, implemented, and
separated in Samakia Fabric.

Clear boundaries are mandatory.
Blurring them leads to operational failure.

---

## 1. Purpose of This Document

This document exists to answer:

- What does Samakia Fabric provide?
- What does it deliberately NOT provide?
- Where does responsibility shift from infrastructure to platform?

Without these answers, automation becomes unsafe.

---

## 2. Definitions (Practical, Not Marketing)

### 2.1 Infrastructure as a Service (IaaS)

In Samakia Fabric, IaaS means:

> Providing compute, network, and storage primitives
> with predictable lifecycle and automation interfaces.

IaaS answers:
- Where does this run?
- How is it created, destroyed, replaced?
- How is it secured at the infrastructure level?

---

### 2.2 Platform as a Service (PaaS)

In Samakia Fabric, PaaS means:

> Providing opinionated runtime platforms
> on top of infrastructure primitives.

PaaS answers:
- How do applications run?
- How are they deployed?
- How are they scaled and observed?

---

## 3. Samakia Fabric’s Position

**Samakia Fabric is primarily an IaaS framework.**

It also **enables** PaaS layers,
but does not conflate itself with them.

This distinction is intentional.

---

## 4. What Samakia Fabric Provides (IaaS)

Samakia Fabric provides:

- Proxmox-based compute orchestration
- LXC and VM lifecycle management
- Network primitives (bridges, VLANs, SDN)
- Storage attachment and placement
- Golden image pipelines (Packer)
- Declarative provisioning (Terraform)
- Configuration enforcement (Ansible)

This is the **infrastructure substrate**.

---

## 5. What Samakia Fabric Does NOT Provide

Samakia Fabric does NOT provide:

- Application runtimes by default
- Opinionated developer platforms
- Managed databases as a service
- Auto-scaling application logic
- CI/CD pipelines for application code

These belong to **PaaS layers above Fabric**.

---

## 6. Enabling PaaS on Top of Fabric

Fabric is designed to **host PaaS platforms**, such as:

- Kubernetes clusters
- Database platforms (Postgres, Redis, etc.)
- Message brokers
- Internal developer platforms (IDPs)

Fabric does not replace them.
It **stabilizes** them.

---

## 7. Terraform Boundary

Terraform is used for:

- IaaS resource declaration
- Placement and lifecycle control
- Infrastructure intent

Terraform is NOT used for:
- Application deployment
- Runtime orchestration
- Service-level logic

Crossing this boundary creates drift.

---

## 8. Ansible Boundary

Ansible is used for:

- OS-level configuration
- Security baselines
- Runtime prerequisites

Ansible is NOT used for:
- Day-to-day application changes
- Continuous mutation of workloads
- Platform orchestration

Ansible prepares platforms, it does not replace them.

---

## 9. Kubernetes as PaaS (Optional Layer)

When Kubernetes is deployed:

- Kubernetes is the PaaS
- Samakia Fabric remains the IaaS

Responsibilities shift clearly:
- Fabric manages nodes
- Kubernetes manages workloads

Mixing control planes is forbidden.

---

## 10. Comparison with Cloud Providers

| Concept | AWS / GCP | Samakia Fabric |
|------|-----------|----------------|
| Compute | EC2 / GCE | Proxmox LXC / VM |
| IaaS API | Cloud API | Terraform + Proxmox |
| Images | AMIs | Packer LXC images |
| PaaS | EKS / GKE | Optional Kubernetes |
| Control | Provider-managed | Operator-managed |

Fabric adopts cloud **patterns**, not cloud **illusions**.

---

## 11. Why This Separation Matters

Clear IaaS / PaaS separation:

- Improves security boundaries
- Simplifies incident response
- Enables independent evolution
- Prevents automation abuse

Most failed platforms fail here.

---

## 12. Anti-Patterns (Explicitly Rejected)

- Treating IaaS as application platform
- Running app logic in Terraform
- SSH-driven “platforms”
- Mixing infra and app concerns
- Hiding PaaS complexity inside IaaS code

These destroy maintainability.

---

## 13. IaaS, PaaS, and Immutability

- IaaS resources are immutable by default
- PaaS workloads may be dynamic
- Boundaries prevent mutation leakage

Immutability is enforced at the IaaS layer.

---

## 14. IaaS, PaaS, and HA

- Fabric provides HA primitives
- PaaS layers consume them intentionally
- HA is not automatic across layers

Availability is a shared responsibility.

---

## 15. Summary

In Samakia Fabric:

- Fabric = IaaS foundation
- PaaS is layered, not embedded
- Boundaries are explicit
- Automation respects responsibility lines

If you cannot explain where IaaS ends
and PaaS begins, the system is unsafe.
