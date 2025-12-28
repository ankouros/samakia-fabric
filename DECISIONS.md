# Architecture Decision Records (ADR) — Samakia Fabric

This document records **key architectural and operational decisions**
made in the Samakia Fabric project.

The purpose of this file is:

- Preserve design intent
- Explain trade-offs
- Prevent accidental regressions
- Enable informed future changes

This document is authoritative.

---

## ADR-0001 — Infrastructure as Code as the Primary Control Plane

**Status:** Accepted
**Date:** 2025-12-26

### Decision

All infrastructure must be managed via **Infrastructure as Code (IaC)**.
Manual changes are considered temporary and must be reconciled back into code.

### Rationale

- Prevents configuration drift
- Enables reproducibility
- Enables safe automation and AI agents
- Improves auditability

### Consequences

- Manual fixes are discouraged
- Emergency changes must be documented and codified afterward

---

## ADR-0002 — Proxmox as the Primary Virtualization Platform

**Status:** Accepted
**Date:** 2025-12-26

### Decision

Samakia Fabric is built around **Proxmox VE** as the base virtualization layer.

### Rationale

- Strong LXC support
- Open ecosystem
- On-prem friendly
- HA, SDN, and storage integration

### Consequences

- Terraform provider limitations are accepted
- Design avoids unsupported or unstable Proxmox API features

---

## ADR-0003 — LXC Preferred Over VMs

**Status:** Accepted
**Date:** 2025-12-26

### Decision

**LXC containers** are the default compute unit.
VMs are used only when explicitly required.

### Rationale

- Lower resource overhead
- Faster provisioning
- Better density
- Sufficient isolation for most workloads

### Consequences

- Containers are treated as disposable
- Kernel is shared and must be trusted
- Feature flags must be immutable

---

## ADR-0004 — Golden Images Must Be Generic

**Status:** Accepted
**Date:** 2025-12-26

### Decision

Golden images must:
- Contain no users
- Contain no SSH keys
- Contain no environment-specific configuration

### Rationale

- Reusability
- Security
- Clean separation of concerns

### Consequences

- All customization happens post-provisioning
- Ansible is responsible for user and policy configuration

---

## ADR-0005 — Terraform Is Not a Provisioner

**Status:** Accepted
**Date:** 2025-12-26

### Decision

Terraform is used **only** for infrastructure lifecycle management.
It must not perform OS or application provisioning.

### Rationale

- Clear responsibility boundaries
- Predictable plans
- Reduced blast radius

### Consequences

- No `remote-exec`
- No `file` provisioners
- Provisioning belongs to Ansible

---

## ADR-0006 — Ansible for OS Configuration and Policy

**Status:** Accepted
**Date:** 2025-12-26

### Decision

Ansible is responsible for:
- User management
- SSH configuration
- sudo policy
- OS hardening

### Rationale

- Idempotent configuration
- Human-readable intent
- Mature ecosystem

### Consequences

- Ansible must remain idempotent
- No infrastructure creation logic allowed

---

## ADR-0007 — Delegated Proxmox User for Automation

**Status:** Accepted
**Date:** 2025-12-26

### Decision

Automation (Terraform) must run using a **delegated Proxmox user**,
never `root@pam`.

### Rationale

- Principle of least privilege
- Reduced blast radius
- Auditable access

### Consequences

- Some Proxmox features are intentionally unavailable
- Terraform must avoid forbidden mutations (e.g. feature flags)

---

## ADR-0008 — Immutable LXC Feature Flags

**Status:** Accepted
**Date:** 2025-12-27

### Decision

LXC feature flags (nesting, keyctl, etc.) are immutable after creation.

### Rationale

- Proxmox API restrictions
- Permission limitations
- Stability

### Consequences

- Feature flags must be decided at creation time
- Terraform ignores feature drift

---

## ADR-0009 — Rebuild Over Repair

**Status:** Accepted
**Date:** 2025-12-27

### Decision

Broken containers should be **destroyed and recreated**, not repaired in place.

### Rationale

- Faster recovery
- Less entropy
- Predictable state

### Consequences

- Containers are treated as cattle
- Persistent data must live outside containers

---

## ADR-0010 — SSH Key-Only Access

**Status:** Accepted
**Date:** 2025-12-27

### Decision

SSH access is **key-only**.
Password authentication is forbidden.

### Rationale

- Stronger security
- Automation-friendly
- Auditable access

### Consequences

- SSH keys must be managed carefully
- Bootstrap flow must be respected

---

## ADR-0011 — Documentation as a First-Class Artifact

**Status:** Accepted
**Date:** 2025-12-27

### Decision

Documentation is treated as a **core part of the system**, not an afterthought.

### Rationale

- Enables safe collaboration
- Enables AI agents
- Reduces operational risk

### Consequences

- Changes require documentation updates
- Missing documentation is considered a defect

---

## ADR-0012 — AI Agents Are First-Class Contributors

**Status:** Accepted
**Date:** 2025-12-27

### Decision

The project is designed to be operated and extended by **AI agents**
following explicit rules (`AGENTS.md`).

### Rationale

- Future-proof collaboration
- Deterministic automation
- Reduced human error

### Consequences

- Rules must be explicit
- Ambiguity is a bug

---

## How to Add a New Decision

1. Add a new ADR entry
2. Use the next incremental ID
3. Clearly state:
   - Decision
   - Rationale
   - Consequences
4. Reference related ADRs if applicable

Unrecorded decisions are considered invalid.

---

## Final Note

If you find yourself asking:
> “Why was this done this way?”

The answer **must exist in this file**.

If it doesn’t:
- Add it.
- Or reconsider the change.
