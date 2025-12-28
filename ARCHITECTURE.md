# Samakia Fabric – Architecture

## 1. Purpose

This document describes the **architecture, design decisions, and operational model**
of the Samakia Fabric project.

Samakia Fabric is designed as a **production-grade, open-source infrastructure framework**
focused on:

- Predictability
- Immutability
- Least privilege
- Clear separation of responsibilities
- Long-term operability

This document is authoritative.
Implementation must follow the architecture described here.

---

## 2. High-Level Architecture

Samakia Fabric is built as a **layered system**, where each layer has **strict ownership**
over a specific responsibility.

```text
┌──────────────────────────────┐
│ Applications                 │
│ (out of scope for Fabric)    │
└───────────────▲──────────────┘
                │
┌───────────────┴──────────────┐
│ Ansible                      │
│ Users · Policy · Day-2       │
└───────────────▲──────────────┘
                │
┌───────────────┴──────────────┐
│ Terraform                    │
│ LXC · Network · Storage      │
└───────────────▲──────────────┘
                │
┌───────────────┴──────────────┐
│ Packer                       │
│ Golden Images (Ubuntu)       │
└───────────────▲──────────────┘
                │
┌───────────────┴──────────────┐
│ Proxmox VE 9                 │
│ LXC · Storage · HA           │
└──────────────────────────────┘
```


Each layer **must not leak responsibilities** into adjacent layers.

---

## 3. Core Principles

### 3.1 Separation of Concerns

| Layer     | Owns                                | Must NOT Own           |
|-----------|-------------------------------------|------------------------|
| Packer    | OS, SSH daemon, image hygiene        | Users, keys, policy    |
| Terraform | Infrastructure lifecycle             | OS configuration       |
| Ansible   | Users, sudo, SSH policy              | Infrastructure         |
| Proxmox   | Hypervisor, security                 | Application logic      |

Violating this separation is considered an architectural defect.

---

### 3.2 Immutability

- Golden images are immutable artifacts
- Template changes trigger **destroy/recreate**
- In-place mutation of base images is forbidden
- Drift is treated as an error, not a feature

---

### 3.3 Least Privilege

- Terraform runs with a **delegated Proxmox user**
- `root@pam` is never required for day-to-day operations
- LXC containers run **unprivileged by default**
- Root SSH access is temporary and tightly controlled

---

## 4. Proxmox Layer

### 4.1 Platform Choice

- Proxmox VE 9
- LXC preferred over VMs where possible
- Explicit storage (e.g. NFS, ZFS) is mandatory

### 4.2 Security Model

- LXC feature flags are **host-level security controls**
- Feature flags are immutable post-creation
- Terraform must not manage feature flags when using delegated users

### 4.3 Networking

- Containers attach to explicit bridges (e.g. `vmbr0`)
- DHCP is acceptable initially
- Long-term DNS / IPAM integration is planned

---

## 5. Packer Layer (Golden Images)

### 5.1 Image Scope

Golden images include:
- Ubuntu 24.04 LTS
- SSH daemon enabled
- Password authentication disabled
- Clean machine-id
- No users
- No application software

Golden images do NOT include:
- SSH authorized keys
- Environment-specific configuration
- Monitoring agents
- Application runtimes

### 5.2 Artifact Contract

- Output format: `*.tar.gz`
- Compatible with Proxmox LXC templates
- Reproducible builds
- CI-safe execution

---

## 6. Terraform Layer (Infrastructure)

### 6.1 Module Design

Terraform modules are:
- Small
- Explicit
- Environment-agnostic
- Stateless beyond declared resources

Terraform environments:
- Live under `terraform/envs/*`
- Own provider configuration
- Own state

Modules never reference:
- Hardcoded IPs
- Secrets
- Environment-specific paths

---

### 6.2 Lifecycle Semantics

- Template change → destroy & recreate
- Compute change → in-place update (if supported)
- Storage change → explicit recreation

This behavior is intentional.

---

### 6.3 Drift Management

Terraform uses:
- Explicit `ignore_changes` guards
- Minimal reliance on API defaults
- Clear expectations about Proxmox normalization behavior

---

## 7. Ansible Layer (Configuration & Policy)

### 7.1 Responsibilities

Ansible is responsible for:
- User lifecycle
- SSH authorized_keys
- Sudo policy
- OS-level hardening
- Day-1 and Day-2 configuration

Ansible is NOT responsible for:
- Creating containers
- Managing Proxmox
- Handling storage or networking

---

### 7.2 Bootstrap Model

1. Temporary root SSH access (key-only)
2. Ansible creates non-root operator user
3. SSH keys installed
4. Passwordless sudo configured
5. Root SSH access disabled

This process is:
- Idempotent
- Auditable
- Repeatable

---

## 8. State & Inventory Flow

```text
Terraform State
     │
     ▼
terraform output (structured)
     │
     ▼
Ansible Inventory
     │
     ▼
Configuration Enforcement
```


Ansible inventory should be:
- Generated
- Not handwritten
- Derived from Terraform outputs

---

## 9. High Availability Considerations

Samakia Fabric is HA-aware by design:
- Explicit VMID control
- Storage abstraction
- Tag-based grouping
- Pool-ready architecture

HA orchestration (anti-affinity, fencing, quorum) is **intentionally decoupled**
from the core framework.

---

## 10. What Is Intentionally Out of Scope

- Application deployment
- Kubernetes
- Service meshes
- CI/CD pipelines
- Observability stacks

Samakia Fabric is an **infrastructure substrate**, not a platform opinionator.

---

## 11. Architectural Guardrails

The following are considered violations:

- Baking users into images
- Using root@pam for Terraform
- Managing Proxmox manually outside code
- Introducing snowflake behavior
- Mixing provisioning into Terraform

---

## 12. Evolution Strategy

Architecture evolves by:
- Versioned golden images
- Backward-compatible Terraform modules
- Explicit breaking changes
- Documentation-first changes

No silent refactors.

---

## 13. Final Statement

Samakia Fabric is designed for **operators, not demos**.

If a design choice optimizes for convenience over clarity,
it is considered incorrect—even if it works.
