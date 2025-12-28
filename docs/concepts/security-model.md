# Security Model in Samakia Fabric

This document describes the **conceptual security model** of Samakia Fabric.

It explains:
- Trust boundaries
- Access models
- Privilege separation
- Failure assumptions
- Incident response posture

This is not a checklist.
It is the **mental model** that informs all security decisions.

---

## 1. Core Security Philosophy

Samakia Fabric is built on the following assumptions:

- Breaches can happen
- Credentials can leak
- Humans and automation make mistakes
- Internal networks are not inherently trusted

Security is achieved through **architecture**, not trust.

---

## 2. Zero Trust Posture

Samakia Fabric adopts a **Zero Trust mindset**:

- No implicit trust based on network location
- No permanent trust based on identity alone
- Every action must be explicitly authorized
- Privileges are scoped and revocable

Zero Trust here is **pragmatic**, not theoretical.

---

## 3. Trust Boundaries

Security boundaries are explicit and enforced.

### 3.1 Boundary Layers

| Layer | Trust Level | Responsibility |
|-----|-------------|----------------|
| Physical host | Highest | Physical & hypervisor security |
| Proxmox VE | High | Virtualization, isolation, ACLs |
| Terraform | Medium | Controlled automation |
| Ansible | Medium | OS-level policy |
| Containers | Low | Disposable execution units |
| Network | Untrusted | Treated as hostile by default |

No layer is allowed to bypass another.

---

## 4. Identity & Access Model

### 4.1 Human Access

Humans:
- Authenticate via SSH keys
- Use non-root users
- Escalate via sudo (auditable)
- Do not share accounts

There are no “admin passwords”.

---

### 4.2 Automation Access

Automation:
- Uses delegated Proxmox users
- Never uses `root@pam`
- Has only explicitly granted privileges
- Is traceable and revocable

If automation requires root privileges,
the design is wrong.

---

## 5. Proxmox Security Controls

Proxmox VE provides:

- Role-based access control (RBAC)
- ACL scoping
- API authentication
- LXC isolation primitives

Samakia Fabric relies on Proxmox for:
- Strong isolation
- Permission enforcement
- Auditability

Terraform must work **within** these constraints.

---

## 6. LXC Container Security

Containers are:

- Unprivileged by default
- Feature-limited (nesting disabled unless required)
- Treated as ephemeral
- Recreated on failure

Security model:
- Compromise = destroy & rebuild
- No attempt to “clean” compromised containers

---

## 7. SSH Security Model

SSH is the primary access vector and is strictly controlled.

Rules:
- Key-only authentication
- Password authentication disabled
- Root SSH access temporary and controlled
- SSH keys managed via code

SSH misconfiguration is treated as a **security incident**.

---

## 8. Secrets & Sensitive Data

Samakia Fabric assumes:

- Secrets will exist
- Secrets will eventually leak

Mitigation strategy:
- Minimize secret scope
- Rotate aggressively
- Externalize secret storage
- Never commit secrets to Git

Secrets do not live in images or Terraform code.

---

## 9. Network Security Model

Networking is treated as **hostile**.

Implications:
- Containers must defend themselves
- No reliance on “internal-only” assumptions
- Explicit firewalling is expected
- Lateral movement is assumed possible

Trust is never inferred from IP ranges alone.

---

## 10. Security and Immutability

Immutability strengthens security by:

- Limiting attacker persistence
- Simplifying incident response
- Reducing configuration drift

A compromised system is **replaced**, not repaired.

---

## 11. Incident Response Model

### 11.1 Detection

Incidents may be detected via:
- Logs
- Alerts
- Unexpected behavior
- Failed integrity checks

Detection is imperfect by assumption.

---

### 11.2 Response

Default response:
1. Isolate (logically or by destruction)
2. Destroy affected container
3. Recreate from known-good state
4. Rotate credentials if needed
5. Audit recent changes

Speed and containment matter more than forensics.

---

## 12. Security and GitOps

GitOps strengthens security by:
- Eliminating undocumented changes
- Providing audit trails
- Enforcing review before change
- Making rollback deterministic

Security incidents must be reconciled back into Git.

---

## 13. Security and AI Agents

AI agents are treated as **untrusted operators**.

Rules:
- They operate via Git only
- They cannot bypass reviews
- They cannot modify state directly
- Their actions must be auditable

AI safety depends on clear boundaries.

---

## 14. Anti-Patterns (Explicitly Rejected)

- Shared credentials
- Password-based access
- Permanent root access
- Manual “hotfixes” without code
- Security through obscurity

These patterns are incompatible with Samakia Fabric.

---

## 15. Summary

In Samakia Fabric:

- Trust is minimized
- Privileges are explicit
- Systems are disposable
- Breaches are assumed
- Recovery is designed-in

If a security decision relies on trust,
it must be rethought.
