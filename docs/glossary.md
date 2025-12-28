# Samakia Fabric — Glossary

This glossary defines **canonical terminology** used throughout the Samakia Fabric repository.

All contributors (human or AI) MUST use these terms consistently.
If a term is ambiguous, it must be clarified here.

---

## A

### Ansible
A configuration management tool used in Samakia Fabric **only** for OS-level configuration, policy enforcement, and post-provisioning tasks.

Ansible does **not** create infrastructure.

---

### Artifact
A generated, versioned output of a build process.
Examples:
- LXC root filesystem tarball
- Terraform plan output

Artifacts must be immutable and reproducible.

---

## B

### Bootstrap
The initial configuration phase of a newly created container, typically performed via Ansible using temporary root access.

Bootstrap establishes:
- Non-root users
- SSH keys
- sudo policy

---

## C

### Cattle (vs Pets)
A philosophy where systems are treated as disposable and replaceable.

In Samakia Fabric:
- Containers are cattle
- Manual repair is discouraged
- Rebuild is preferred

---

### Cloud-Init
A mechanism for injecting initial configuration (e.g. SSH keys) into a system at first boot.

In Samakia Fabric, cloud-init is used **minimally** and declaratively.

---

### Container (LXC)
The primary compute unit in Samakia Fabric.
Containers are:
- Unprivileged by default
- Disposable
- Recreated via Terraform

---

## D

### Delegated Proxmox User
A non-root Proxmox account with explicitly scoped permissions used by automation tools (Terraform).

This user enforces least privilege and auditability.

---

### Drift
A state where real infrastructure differs from the declared IaC configuration.

Drift is considered a defect.

---

## F

### Feature Flags (LXC)
Proxmox LXC configuration options such as `nesting`, `keyctl`, or `fuse`.

In Samakia Fabric, feature flags are **immutable after creation**.

---

## G

### Golden Image
A minimal, generic base OS image used to create containers.

Golden images:
- Contain no users
- Contain no SSH keys
- Are versioned
- Are environment-agnostic

---

## H

### Hypervisor
The system responsible for running containers and VMs.
In Samakia Fabric, this is Proxmox VE.

---

## I

### IaC (Infrastructure as Code)
The practice of managing infrastructure through declarative code.

In Samakia Fabric:
- Terraform is the primary IaC tool
- Manual changes must be reconciled back into code

---

### Immutable Infrastructure
An approach where systems are replaced rather than modified in place.

Samakia Fabric favors immutability wherever possible.

---

## L

### LXC
Linux Containers, used as the default workload runtime.

Chosen for efficiency, speed, and density.

---

## M

### Module (Terraform)
A reusable unit of Terraform code encapsulating a single responsibility.

Modules must be generic and environment-agnostic.

---

## O

### Operator
A human responsible for deploying, maintaining, or operating the infrastructure.

Operators are expected to follow documented procedures.

---

## P

### Packer
A tool used to build golden images in Samakia Fabric.

Packer is responsible only for image creation, not deployment.

---

### Proxmox VE
The virtualization platform used as the foundation of Samakia Fabric.

Provides:
- LXC
- Storage integration
- HA primitives
- Access control

---

## R

### Rebuild Over Repair
An operational principle favoring system replacement over manual fixes.

This reduces entropy and improves reliability.

---

### Root Access
Administrative access to a system.

In Samakia Fabric:
- Root SSH access is temporary
- Long-term operations use non-root users
- Automation must not rely on root@pam

---

## S

### Samakia Fabric
The name of the infrastructure framework defined by this repository.

Samakia Fabric is:
- Proxmox-centric
- LXC-first
- IaC-driven
- Security-focused

---

### SSH Key-Only Access
A security model where authentication is performed exclusively using SSH keys.

Passwords are forbidden.

---

### State (Terraform)
The recorded representation of deployed infrastructure.

Terraform state is critical and must be protected.

---

## T

### Terraform
The primary tool for infrastructure lifecycle management.

Terraform creates, modifies, and destroys infrastructure resources, but does not configure OS-level details.

---

### Template (LXC)
A prebuilt LXC root filesystem used to create containers.

Templates must exist in Proxmox before Terraform references them.

---

## U

### Unprivileged Container
An LXC container that runs without host-level root privileges.

This is the default and recommended mode.

---

## V

### VM (Virtual Machine)
A fully virtualized compute unit.

VMs are supported but not the default in Samakia Fabric.

---

## Z

### Zero Trust
A security mindset where no component is trusted by default.

Samakia Fabric assumes:
- Networks can be compromised
- Credentials can leak
- Systems must defend themselves

---

## Glossary Governance

- New terms must be added here before use
- Terms must be used consistently across documentation and code
- Ambiguous language is considered a defect

---

## Final Note

A shared vocabulary is a form of infrastructure.

If contributors do not agree on words, they will not agree on systems.
