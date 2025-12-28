# Samakia Fabric – AGENTS.md

This document defines **how automated agents (AI assistants, Codex, CI bots, contributors) must operate** inside the Samakia Fabric repository.

It is a **hard contract**, not a suggestion.

---

## 1. Project Overview

**Samakia Fabric** is an open-source, production-grade infrastructure framework built on:

- Proxmox VE 9
- LXC (preferred over VMs where possible)
- Packer for golden image creation
- Terraform for infrastructure provisioning
- Ansible for bootstrap, users, and policy
- SSH key-only access
- Delegated Proxmox users (not root@pam)

Core principles:
- Immutability
- Idempotency
- Least privilege
- GitOps-style workflows
- Clear separation of responsibilities

---

## 2. Layer Responsibilities (NON-NEGOTIABLE)

### 2.1 Packer (Golden Images)
Packer is responsible ONLY for:
- Base OS installation
- SSH daemon availability
- System hardening at OS level
- Image hygiene (machine-id, ssh host keys reset)

Packer MUST NOT:
- Create users
- Install application software
- Inject SSH keys for specific operators
- Encode environment-specific logic

Golden images must remain **generic and reusable**.

---

### 2.2 Terraform (Infrastructure)
Terraform is responsible ONLY for:
- LXC lifecycle (create / destroy / replace)
- Compute resources (CPU, memory, disk)
- Networking attachment
- Explicit storage selection
- Metadata (tags, VMID, placement)

Terraform MUST NOT:
- Create users inside containers
- Manage OS-level configuration
- Modify LXC feature flags post-creation
- Depend on root@pam privileges
- Perform provisioning logic

Terraform operates with a **delegated Proxmox user**, not root.

---

### 2.3 Ansible (Configuration & Policy)
Ansible is responsible for:
- User creation
- SSH authorized_keys
- Sudo configuration
- OS-level policy
- Day-1 / Day-2 configuration

Ansible MUST:
- Be idempotent
- Assume containers start in a minimal, generic state
- Disable root SSH access after bootstrap

Ansible MUST NOT:
- Provision infrastructure
- Modify Proxmox resources
- Replace Terraform logic

---

## 3. Proxmox-Specific Rules

- LXC feature flags (`keyctl`, `nesting`, `fuse`, etc.) are **host-level security controls**
- Feature flags MUST NOT be modified by Terraform when using delegated users
- Feature flags are treated as **immutable**
- Storage MUST always be explicit (never rely on `local` implicitly)

---

## 4. Security Model

- SSH access is **key-only**
- Password authentication is forbidden
- Root SSH access is allowed **only temporarily** for bootstrap
- Long-term access must use a non-root user
- Unprivileged LXC containers are the default

Any change that weakens these guarantees is considered a **security regression**.

---

## 5. Repository Structure Expectations

Agents must respect the following structure:

- `fabric-core/packer/` → golden images only
- `fabric-core/terraform/modules/` → reusable Terraform modules
- `fabric-core/terraform/envs/` → executable Terraform environments
- `fabric-core/ansible/` → configuration, bootstrap, roles

Agents MUST NOT:
- Run Terraform inside `modules/`
- Mix environment logic into reusable modules
- Hardcode IPs or secrets into code

---

## 6. Terraform Rules for Agents

- Always run Terraform commands from an `envs/*` directory
- Use explicit variables and outputs
- Do not introduce implicit dependencies
- Use `ignore_changes` guards where Proxmox API normalization causes drift
- Assume destroy/recreate is acceptable for template changes

---

## 7. Ansible Rules for Agents

- Inventory should be derived from Terraform outputs where possible
- Avoid static IPs unless explicitly required
- Prefer roles over monolithic playbooks
- Ensure all playbooks are safe to re-run

---

## 8. What Agents SHOULD Do

- Propose changes with minimal scope
- Preserve existing contracts and abstractions
- Prefer explicitness over convenience
- Flag risky changes instead of silently implementing them
- Ask before introducing new tools or layers

---

## 9. What Agents MUST NOT Do

- Bake policy or users into golden images
- Assume root@pam access
- Modify Proxmox configuration outside Terraform
- Bypass Ansible with ad-hoc shell provisioning
- Introduce snowflake behavior

---

## 10. Design Philosophy

Samakia Fabric prioritizes:
- Long-term operability over short-term convenience
- Predictability over cleverness
- Clear ownership of responsibility per layer

Any contribution or automation that violates these principles is considered incorrect, even if it “works”.

---

## 11. Final Note to Agents

You are operating in a **production-oriented infrastructure codebase**.

If a change feels “easy but dirty”, it is almost certainly wrong.

When in doubt:
- Stop
- Explain the risk
- Propose a clean alternative
