# State Management in Samakia Fabric

This document defines **how state is understood, managed, protected,
and recovered** in Samakia Fabric.

State is one of the most critical operational concerns.
Mismanagement of state leads directly to outages and data loss.

---

## 1. What “State” Means Here

In Samakia Fabric, **state** is:

> Any data that represents the current or historical condition of the system
> and is required for correct operation or recovery.

State is not limited to Terraform.

---

## 2. Categories of State

Samakia Fabric recognizes **four distinct categories of state**.

### 2.1 Declarative State (Authoritative)

Examples:
- Terraform configuration
- Ansible playbooks and roles
- Packer image definitions
- Documentation (ADRs, OPERATIONS)

Properties:
- Stored in Git
- Human- and AI-readable
- Version-controlled
- Reviewable

**Git is the source of truth** for declarative state.

---

### 2.2 Control State (Terraform State)

Examples:
- `terraform.tfstate`
- Remote backend metadata
- Provider resource mappings

Properties:
- Machine-generated
- Critical for safe operation
- Must never be edited manually

Terraform state represents **how declared intent maps to real resources**.

---

### 2.3 Runtime State

Examples:
- Running containers
- Ephemeral files
- Process memory
- Temporary caches

Properties:
- Short-lived
- Disposable
- Recreated on rebuild

Runtime state is **never authoritative**.

---

### 2.4 Persistent Data State

Examples:
- Databases
- User data
- Backups
- External volumes

Properties:
- Long-lived
- Must survive rebuilds
- Must be explicitly protected

Persistent data must be **decoupled from container identity**.

---

## 3. State Ownership Model

| State Type | Owner | Tool |
|----------|------|------|
| Declarative | Git | Git |
| Control | Terraform | Terraform backend |
| Runtime | Proxmox | LXC |
| Persistent Data | Operator / Platform | Storage systems |

No tool is allowed to manage state outside its responsibility.

---

## 4. Terraform State Management

### 4.1 Authoritative Role

Terraform state is authoritative for:
- Resource existence
- Resource identity
- Resource lifecycle

If Terraform state is lost or corrupted, **operations must stop**.

---

### 4.2 Storage of Terraform State

Recommended:
- Remote backend (S3 / MinIO)
- State locking enabled
- Access restricted to automation users

Not recommended:
- Local-only state for shared environments
- Manual copying of state files

---

### 4.3 State Drift

Drift occurs when:
- Manual changes are made in Proxmox
- State is modified outside Terraform
- Resources are deleted manually

Drift resolution:
1. Detect via `terraform plan`
2. Decide: reconcile or rebuild
3. Apply change via Terraform

Manual reconciliation without code is forbidden.

---

## 5. Ansible and State

Ansible does **not** maintain state in the Terraform sense.

Instead:
- Ansible enforces *desired configuration*
- It assumes idempotency
- It reconciles differences at runtime

Ansible must never be used to track infrastructure identity.

---

## 6. State and Immutability

Immutability simplifies state management by:

- Reducing in-place mutation
- Making replacement the default
- Limiting hidden state

If a component cannot be safely replaced,
its state boundaries are wrong.

---

## 7. State and GitOps

GitOps relies on correct state management:

- Git defines desired state
- Terraform state maps intent → reality
- Runtime state is disposable
- Persistent state is externalized

If state cannot be reconciled via Git,
GitOps breaks down.

---

## 8. Failure Scenarios

### 8.1 Terraform State Loss

If Terraform state is lost:

1. Stop all automation
2. Restore from backend backup
3. If restore is impossible:
   - Re-import resources carefully
   - Validate with `terraform plan`
4. Document incident

Blind re-creation is dangerous and discouraged.

---

### 8.2 Container Corruption

If a container is corrupted:

1. Assume runtime state is invalid
2. Destroy container
3. Recreate via Terraform
4. Reapply Ansible
5. Validate persistent data integrity

---

### 8.3 Persistent Data Loss

Persistent data loss is a **platform failure**, not an infra failure.

Mitigation:
- Backups
- Replication
- Clear ownership boundaries

Terraform must never manage application data directly.

---

## 9. Anti-Patterns (Explicitly Rejected)

- Editing Terraform state manually
- Treating runtime state as authoritative
- Storing persistent data inside containers
- Mixing data lifecycle with container lifecycle
- Using Ansible to “fix” Terraform drift

These lead to irrecoverable systems.

---

## 10. State and AI Agents

For AI-assisted operations:

- Git is the only writable interface
- Terraform state is read-only to agents unless explicitly allowed
- Runtime state must not be trusted
- Rebuild is safer than mutation

State clarity is what makes AI safe.

---

## 11. Summary

In Samakia Fabric:

- State is categorized and owned
- Git defines intent
- Terraform tracks control state
- Runtime state is disposable
- Persistent data is protected and external

If state ownership is unclear,
the system is unsafe.
