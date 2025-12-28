# Contributing to Samakia Fabric

Thank you for your interest in contributing to **Samakia Fabric**.

This project is a **production-oriented infrastructure framework**.
Contributions are welcome, but they must strictly follow the architectural,
security, and operational principles defined in this repository.

This document defines **how to contribute correctly**.

---

## Who This Project Is For

Samakia Fabric is designed for:
- Infrastructure engineers
- DevOps practitioners
- Platform operators
- Contributors with real-world Proxmox, Terraform, and Ansible experience

It is **not** designed as:
- A tutorial repository
- A playground for experimental tooling
- A place for convenience-driven shortcuts

---

## Before You Contribute

You MUST read and understand:
- `ARCHITECTURE.md`
- `AGENTS.md`
- `STYLEGUIDE.md`

If your contribution conflicts with any of these documents, it will not be accepted.

---

## Contribution Scope

### What We Accept

We welcome contributions that:
- Improve reliability, clarity, or maintainability
- Extend functionality without breaking contracts
- Improve documentation and operational guidance
- Fix real bugs with clear root cause analysis
- Add guardrails, validations, or safety mechanisms

### What We Do NOT Accept

We do NOT accept contributions that:
- Bake users or policies into golden images
- Require `root@pam` access for Terraform
- Mix provisioning logic into Terraform
- Introduce snowflake behavior
- Hardcode IPs, credentials, or secrets
- Trade correctness for convenience

---

## Layer Ownership Rules (Strict)

| Layer    | Owned Responsibilities                |
|----------|----------------------------------------|
| Packer   | OS base, SSH daemon, image hygiene     |
| Terraform| Infrastructure lifecycle              |
| Ansible  | Users, SSH keys, sudo, OS policy       |
| Proxmox  | Hypervisor, HA, security              |

Contributions MUST respect this separation.

---

## Repository Structure

Contributors MUST respect the existing layout:

```text
fabric-core/
├── packer/
├── terraform/
│   ├── modules/
│   └── envs/
├── ansible/
```

Rules:
- Terraform must only be executed from `envs/*`
- Reusable logic belongs in `modules/*`
- Environment-specific configuration must not leak into modules
- Ansible inventory should be generated, not handwritten

---

## Terraform Contribution Rules

- Format with:

```bash
terraform fmt -recursive
```

- No implicit defaults for storage, bridge, or VMID
- Lifecycle behavior must be explicit (destroy/recreate is acceptable)
- Delegated Proxmox users only
- LXC feature flags are immutable and must not be managed dynamically

Any change that increases blast radius must be clearly documented.

---

## Packer Contribution Rules

Golden images must:
- Remain generic and reusable
- Contain no users or SSH keys
- Disable password authentication
- Reset machine-id and SSH host keys
- Produce reproducible `tar.gz` artifacts

Image-specific customization belongs in Ansible, not Packer.

---

## Ansible Contribution Rules

Ansible code must:
- Be idempotent
- Avoid shell where modules exist
- Use roles for reusable logic
- Disable root SSH access after bootstrap

Ansible must never:
- Provision infrastructure
- Replace Terraform responsibilities
- Introduce imperative one-off behavior

---

## Commit and Pull Request Guidelines

### Commits

- Use clear, descriptive commit messages
- Prefer small, focused commits
- Avoid mixing unrelated changes

Examples:

```text
terraform: add validation for LXC template path
packer: reset machine-id during image build
docs: clarify bootstrap SSH model
```

### Pull Requests

Pull requests MUST include:
- Clear description of the change
- Motivation and problem statement
- Any risks or trade-offs
- Confirmation that formatting and validation were run

Large refactors require prior discussion.

---

## Security Considerations

Security regressions are taken seriously.

Do NOT:
- Weaken SSH access controls
- Introduce password-based authentication
- Expand privileges unnecessarily
- Bypass defined guardrails

If in doubt, open an issue before submitting a PR.

---

## Versioning and Compatibility

- Breaking changes must be explicit
- Golden image changes require version bumps
- Terraform module contracts must remain stable or versioned
- No silent behavioral changes

---

## Decision Making

Design decisions should:
- Favor clarity over cleverness
- Favor explicitness over automation
- Favor long-term operability over short-term convenience

If a change “feels dirty,” it probably is.

---

## Final Notes

Samakia Fabric is built for operators, not demos.

If you are unsure about a contribution:
- Ask first
- Explain the problem
- Propose a clean solution

We value correctness, restraint, and discipline.
