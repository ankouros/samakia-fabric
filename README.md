# Samakia Fabric

**Samakia Fabric** is a production-grade, open infrastructure framework for building and operating
**Proxmox-based, LXC-first platforms** using Infrastructure as Code.

It is designed for:

- Infrastructure engineers
- DevOps / SRE teams
- Platform operators
- AI-assisted operations

Samakia Fabric is **not** a demo or tutorial repository.
It is a **reference-quality infrastructure fabric**.

---

## What Samakia Fabric Is

Samakia Fabric provides a **clean, disciplined, and opinionated** approach to:

- Golden image creation (Packer)
- Infrastructure lifecycle management (Terraform)
- OS configuration and policy (Ansible)
- Secure, delegated automation on Proxmox VE
- LXC-first workloads with rebuild-over-repair philosophy

The goal is **operability, clarity, and long-term maintainability**.

---

## What Samakia Fabric Is Not

Samakia Fabric is **not**:

- A managed service
- A Kubernetes distribution
- A hypervisor abstraction layer
- A beginner playground
- A click-ops replacement

It assumes you want **control**, not convenience.

---

## Core Principles

Samakia Fabric is built around these principles:

- Infrastructure as Code is the source of truth
- LXC containers are preferred over VMs
- Golden images are generic and immutable
- Terraform manages infrastructure, not configuration
- Ansible manages OS policy, not infrastructure
- Rebuild is preferred over repair
- Security is enforced by architecture, not convention

These principles are non-negotiable.

---

## Architecture Overview

At a high level:

- Packer builds golden LXC images
- Terraform creates and manages infrastructure
- Ansible configures OS users, SSH, sudo, policy
- Proxmox VE runs and secures the platform

Each layer has **clear ownership and boundaries**.

For details, see:

- `ARCHITECTURE.md`
- `DECISIONS.md`

---

## Repository Structure

```text
fabric-core/
├── packer/        # Golden image pipeline
├── terraform/
│   ├── modules/   # Reusable infrastructure modules
│   └── envs/      # Environment definitions (dev/prod)
├── ansible/
│   ├── playbooks/ # Bootstrap & configuration
│   └── roles/     # Reusable OS roles
└── docs/          # Optional diagrams and references
```

Terraform is **only** executed from `envs/*`.

---

## Supported Stack

- **Hypervisor**: Proxmox VE (9+)
- **Compute**: LXC (unprivileged by default)
- **IaC**: Terraform (telmate/proxmox provider)
- **Configuration**: Ansible
- **Images**: Packer (Docker-based rootfs build)
- **OS**: Ubuntu LTS (currently 24.04)

---

## Security Model

Samakia Fabric enforces:

- Delegated Proxmox users (no `root@pam` automation)
- SSH key-only access
- No users or keys baked into images
- Immutable LXC feature flags
- Explicit privilege boundaries

Security is documented in:
- `SECURITY.md`
- `OPERATIONS.md`

---

## Documentation Index

This repository is documentation-first.

Start here:

- 📐 `ARCHITECTURE.md`
- 🧠 `DECISIONS.md`
- 🛠️ `OPERATIONS.md`
- 🔐 `SECURITY.md`
- 🎨 `STYLEGUIDE.md`
- 🤝 `CONTRIBUTING.md`
- 🤖 `AGENTS.md`
- 🧭 `ROADMAP.md`
- 📘 `docs/glossary.md`

If something is not documented, it is considered incomplete.

---

## Contribution Model

Contributions are welcome, but **discipline is required**.

Before contributing:
1. Read `CONTRIBUTING.md`
2. Read `STYLEGUIDE.md`
3. Understand `DECISIONS.md`

Pull requests that violate architectural boundaries will be rejected.

---

## AI Agents

Samakia Fabric is explicitly designed to be:
- Readable by AI agents
- Operable by AI agents
- Safe for AI-assisted workflows

Rules for agents are defined in `AGENTS.md`.

---

## License

Samakia Fabric is licensed under the **Apache License 2.0**.

You may:
- Use it commercially
- Modify it
- Fork it

You may not:
- Use the name or branding without permission

See `LICENSE` for details.

---

## Final Statement

Samakia Fabric exists to answer a simple question:

> “What does clean, serious, on-prem infrastructure look like in 2025?”

If you value:
- Explicit design
- Operational calm
- Security by default
- Long-term clarity

Then Samakia Fabric is for you.
