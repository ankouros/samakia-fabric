# Security Policy — Samakia Fabric

Security is a **first-class concern** in Samakia Fabric.

This document defines:
- The security model
- Threat assumptions
- Supported configurations
- Responsible disclosure process

This is not a compliance document.
It is an **operational security policy**.

---

## 1. Security Philosophy

Samakia Fabric follows these principles:

- Least privilege by default
- Explicit access over implicit trust
- Rebuild over repair
- Immutable infrastructure where possible
- Delegated control, not shared root

Security is enforced **by architecture**, not by convention.

Operator safety model: `docs/operator/safety-model.md`.

---

## 2. Threat Model (Assumptions)

We assume:
- Internal networks can be compromised
- Credentials can leak
- Operators can make mistakes
- Automation can fail

We do NOT assume:
- A trusted internal network
- Long-lived credentials are safe
- Manual intervention is reliable

---

## 3. Trust Boundaries

| Boundary | Responsibility |
|--------|----------------|
| Proxmox host | Physical & hypervisor security |
| Terraform | Infrastructure lifecycle |
| Ansible | OS-level policy |
| Containers | Disposable runtime units |
| Operators | Human-in-the-loop approvals |

No layer is allowed to bypass another.

---

## 4. Proxmox Security Model

### 4.1 Access Control

- Terraform uses a **delegated Proxmox user**
- `root@pam` is forbidden for automation
- Privileges are explicitly enumerated
- ACLs are applied at `/` scope intentionally

Any requirement for root access must be documented and reviewed.

---

### 4.2 LXC Security

- Containers are unprivileged by default
- Feature flags are immutable post-creation
- Nesting is disabled unless explicitly required
- Containers are treated as replaceable units

---

## 5. SSH Security Model

### 5.1 Authentication

- SSH key authentication only
- Password authentication is disabled
- Root SSH access is temporary and controlled
- SSH keys are injected via Terraform / Ansible

Failure to enforce this is considered a **security incident**.

---

### 5.2 User Access

- No users exist in golden images
- Users are created via Ansible
- Passwordless sudo is explicit and auditable
- Operator access is revocable via code

---

## 6. Golden Image Security

Golden images MUST:
- Contain no users
- Contain no SSH keys
- Have root password locked
- Reset machine-id
- Remove SSH host keys
- Disable password authentication

Images are **generic, reusable, and minimal**.

---

## 7. Secrets Management

Samakia Fabric does NOT:
- Store secrets in Git
- Hardcode credentials
- Commit `.env` files

Secrets MUST be provided via:
- Environment variables
- External secret managers
- Secure CI/CD pipelines

Terraform variables containing secrets must be marked sensitive.

---

## 8. Terraform Security Rules

Terraform MUST NOT:
- Escalate privileges silently
- Modify immutable LXC feature flags
- Perform provisioning
- Embed credentials in code

Terraform SHOULD:
- Use lifecycle guards
- Fail loudly on permission errors
- Prefer recreate over mutation

---

## 9. Ansible Security Rules

Ansible MUST:
- Be idempotent
- Avoid shell where modules exist
- Disable root SSH after bootstrap

Ansible MUST NOT:
- Re-enable password authentication
- Modify Proxmox configuration
- Store secrets in plaintext

---

## 10. Network Security

- No assumption of trusted VLANs
- Containers must be hardened individually
- Firewalling is expected at higher layers
- Security groups / iptables are explicit concerns

Network openness must be justified, not assumed.
Firewall profiles in Phase 5 are **default-off** and require explicit enable/execute flags.

---

## 11. Audit Logging Baseline

Minimum viable audit trail (MUST be preserved):
- SSH auth events: `/var/log/auth.log` or `journalctl -u ssh`
- Privileged commands: `sudo` events via auth log / journal
- Service logs: systemd journals per service unit

Retention guidance (minimum):
- 7 days local retention for active troubleshooting
- 30 days exported evidence for audit review (signed if required)

Evidence handling:
- Do NOT store secrets in logs or evidence packets.
- Export logs using read-only commands and store under `evidence/` with manifests.
- Use existing compliance snapshot signing workflows for integrity.

---

## 12. Secrets Handling (Vault default)

- Default secrets backend is **Vault** (HA control plane).
- File backend is an explicit exception for bootstrap/CI/local use.
- Backend overrides must be explicit and documented.
- Vault integration for bindings is **read-only** in current tooling.
- Secrets are never committed to Git and never printed in logs.
- Passphrases are provided via environment or local passphrase files.

---

## 13. Incident Response

### 11.1 Suspected Compromise

1. Assume the container is compromised
2. Do NOT attempt manual cleanup
3. Destroy container via Terraform
4. Recreate from known-good image
5. Rotate credentials if required
6. Audit recent changes

---

### 11.2 Credential Leak

1. Revoke exposed credentials immediately
2. Rotate keys
3. Update automation inputs
4. Audit access logs
5. Document incident

---

## 14. Supported Security Posture

Samakia Fabric officially supports:
- Key-only SSH
- Unprivileged LXC
- Delegated Proxmox users
- Immutable infrastructure patterns

Any deviation must be documented and justified.

---

## 15. Responsible Disclosure

If you discover a security vulnerability:

- Do NOT open a public issue
- Do NOT post details publicly

Instead:
- Contact the maintainer directly
- Provide a clear description and reproduction steps
- Allow time for mitigation before disclosure

---

## 16. Out of Scope

The following are out of scope:
- Application-level vulnerabilities
- Kubernetes workload security
- Third-party software CVEs
- User misconfiguration outside documented patterns

---

## 15. Final Statement

Security in Samakia Fabric is **intentional**.

If a shortcut compromises security:
- The shortcut is wrong
- The design must change

Correctness, clarity, and restraint are preferred over convenience.
