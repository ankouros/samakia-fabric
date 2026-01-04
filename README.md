# Samakia Fabric

Samakia Fabric is a production-minded infrastructure framework for building and
operating Proxmox-based, LXC-first platforms with Infrastructure as Code.
We try to keep it clear, deterministic, and auditable.

It is intended for:

- Infrastructure engineers
- DevOps and SRE teams
- Platform operators
- AI-assisted operations

Samakia Fabric is not a demo or tutorial repository.
It aims to be a reference-quality infrastructure fabric.

---

## What This Repository Tries To Provide

Samakia Fabric provides a disciplined approach to:

- Golden image creation (Packer)
- Infrastructure lifecycle management (Terraform)
- OS configuration and policy (Ansible)
- Secure, delegated automation on Proxmox VE
- LXC-first workloads with a rebuild-over-repair philosophy

The goal is operability, clarity, and long-term maintainability.

---

## What This Repository Does Not Try To Be

Samakia Fabric is not:

- A managed service
- A Kubernetes distribution
- A hypervisor abstraction layer
- A beginner playground
- A click-ops replacement

If you need a turnkey or highly automated experience, this may not be the
right fit.

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

We aim to keep these principles consistent across the codebase and docs.

---

## Architecture Overview

At a high level:

- Packer builds golden LXC images
- Terraform creates and manages infrastructure
- Ansible configures OS users, SSH, sudo, and policy
- Proxmox VE runs and secures the platform

Each layer has clear ownership and boundaries.

For details, see:

- `ARCHITECTURE.md`
- `DECISIONS.md`

---

## Repository Structure

```text
fabric-core/
|-- packer/        # Golden image pipeline
|-- terraform/
|   |-- modules/   # Reusable infrastructure modules
|   `-- envs/      # Environment definitions (dev/prod)
|-- ansible/
|   |-- playbooks/ # Bootstrap and configuration
|   `-- roles/     # Reusable OS roles
`-- docs/          # Documentation and references
```

Terraform is only executed from `envs/*`.

---

## Supported Stack

- Hypervisor: Proxmox VE (9+)
- Compute: LXC (unprivileged by default)
- IaC: Terraform (telmate/proxmox provider)
- Configuration: Ansible
- Images: Packer (Docker-based rootfs build)
- OS: Ubuntu LTS (currently 24.04)

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

## Production

Production usage is locked by a go-live acceptance marker and a single operator
happy path. See:

- `docs/operator/PRODUCTION_PLAYBOOK.md`
- `acceptance/GO_LIVE_ACCEPTED.md`

---

## Getting Started

- Read `docs/README.md` for the documentation map.
- Follow `docs/tutorials/README.md` in order for first-time setup.
- Review `CONTRACTS.md` and `SECURITY.md` before making changes.

---

## Documentation Index

This repository is documentation-first.

Start here:

- `ARCHITECTURE.md`
- `DECISIONS.md`
- `OPERATIONS.md`
- `SECURITY.md`
- `CONTRACTS.md`
- `STYLEGUIDE.md`
- `CONTRIBUTING.md`
- `AGENTS.md`
- `ROADMAP.md`
- `docs/glossary.md`

If something is not documented, please treat it as incomplete.

---

## Contribution Model

Contributions are welcome, but discipline is required.

Before contributing:
1. Read `CONTRIBUTING.md`
2. Read `STYLEGUIDE.md`
3. Understand `DECISIONS.md`

Pull requests that violate architectural boundaries will be rejected.

---

## AI Agents

Samakia Fabric is designed to be readable and operable by AI agents.
Rules for agents are defined in `AGENTS.md`.
Shared ecosystem contract: `/home/aggelos/samakia-specs/specs/base/ecosystem.yaml`.

---

## License

Samakia Fabric is licensed under the Apache License 2.0.

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

"What does clean, serious, on-prem infrastructure look like in 2025?"

If you value:
- Explicit design
- Operational calm
- Security by default
- Long-term clarity

We hope this repository is useful.
