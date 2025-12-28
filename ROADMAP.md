# Samakia Fabric – Roadmap

This roadmap outlines the **planned evolution** of Samakia Fabric.

It is not a promise.
It is a **directional guide** based on real operational priorities.

Dates are indicative.
Correctness and stability take precedence over speed.

---

## Guiding Principles

All roadmap items must:
- Respect existing architecture decisions
- Preserve security guarantees
- Avoid breaking changes without explicit versioning
- Remain operable by humans and AI agents

Anything that violates these principles is out of scope.

---

## Phase 0 — Foundation (COMPLETED ✅)

Goal: Establish a solid, production-grade base.

### Completed
- Proxmox-based infrastructure model
- LXC-first strategy
- Golden image pipeline (Packer)
- Terraform modules with Proxmox 9 guards
- Ansible bootstrap & configuration model
- Delegated Proxmox user for automation
- Full documentation set:
  - ARCHITECTURE.md
  - AGENTS.md
  - CONTRIBUTING.md
  - OPERATIONS.md
  - SECURITY.md
  - DECISIONS.md
  - STYLEGUIDE.md

Status: **Stable**

---

## Phase 1 — Operational Hardening (NEXT)

Goal: Make day-2 operations safer and more repeatable.

### Planned
- Remote Terraform state (MinIO / S3 backend)
- State locking
- Explicit environment separation (dev / staging / prod)
- LXC lifecycle guard improvements
- Ansible role hardening (baseline, users, ssh, sudo)
- Inventory validation and sanity checks

Outcome:
- Reduced operator error
- Safer concurrent operations

---

## Phase 2 — Networking & Platform Primitives

Goal: Establish reusable infrastructure building blocks.

### Planned
- Terraform network modules (bridges, VLAN tagging)
- Proxmox SDN integration (optional, guarded)
- Load balancer primitives (HAProxy / Keepalived)
- Shared service containers (DNS, NTP, internal tools)
- Standard tagging and labeling conventions

Outcome:
- Predictable internal networking
- Reusable patterns across projects

---

## Phase 3 — High Availability & Resilience

Goal: Enable resilient, multi-node deployments.

### Planned
- Proxmox HA-aware patterns
- Multi-node placement strategies
- Storage abstraction patterns (NFS, Ceph-ready)
- Failure-domain aware container placement
- Explicit HA/non-HA workload classification

Outcome:
- Controlled redundancy
- Clear failure handling semantics

---

## Phase 4 — GitOps & CI/CD Integration

Goal: Integrate infrastructure lifecycle with Git workflows.

### Planned
- Terraform plan/apply via CI (read-only first)
- Policy-as-code checks
- Pre-merge validation (fmt, validate, lint)
- Optional auto-apply for non-prod
- Drift detection workflows

Outcome:
- Safer change management
- Audit-friendly operations

---

## Phase 5 — Advanced Security & Compliance

Goal: Strengthen security posture without sacrificing operability.

### Planned
- Secrets manager integration
- SSH key rotation workflows
- Host-based firewall patterns
- Enhanced audit logging
- Optional compliance profiles

Outcome:
- Stronger security guarantees
- Clear incident response paths

---

## Phase 6 — Platform Consumers

Goal: Make Samakia Fabric consumable by higher-level platforms.

### Planned
- Kubernetes-ready primitives
- Database service patterns
- Message queue patterns
- Observability stack foundations
- Platform documentation for consumers

Outcome:
- Samakia Fabric as a substrate, not a destination

---

## Phase 7 — AI-Assisted Operations

Goal: Enable safe, bounded AI participation.

### Planned
- Agent task boundaries
- Automated plan review workflows
- Controlled auto-remediation
- Decision enforcement via documentation
- AI-readable runbooks

Outcome:
- Reduced cognitive load
- Safer automation at scale

---

## Non-Goals

The following are explicitly NOT goals:

- Becoming a managed service
- Supporting every hypervisor
- Abstracting away Proxmox specifics
- Hiding infrastructure complexity
- Optimizing for beginners

Samakia Fabric is built for operators who value control.

---

## Versioning Strategy (Planned)

- Semantic versioning
- Major versions may introduce breaking changes
- Golden images versioned independently
- Terraform modules versioned explicitly

---

## How This Roadmap Evolves

This roadmap is:
- Reviewed periodically
- Updated as real needs emerge
- Driven by operational experience

New roadmap items must:
- Reference existing ADRs
- Justify their necessity
- Clearly state trade-offs

---

## Final Note

Samakia Fabric is designed to grow **deliberately**.

If a feature does not improve:
- Safety
- Clarity
- Operability

It does not belong on this roadmap.
