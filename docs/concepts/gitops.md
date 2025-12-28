# GitOps in Samakia Fabric

This document defines what **GitOps means in the context of Samakia Fabric**.

It is intentionally precise and opinionated.
Not everything marketed as “GitOps” applies here.

---

## 1. What GitOps Means Here

In Samakia Fabric, **GitOps means**:

> Git is the single source of truth for infrastructure and configuration,
> and all changes flow through version-controlled, auditable processes.

GitOps is **a control model**, not a tool.

---

## 2. Scope of GitOps

GitOps in Samakia Fabric applies to:

- Terraform infrastructure definitions
- Ansible configuration and policy
- Golden image build definitions (Packer)
- Documentation and architectural decisions

GitOps does NOT directly manage:
- Proxmox itself (hypervisor ops remain manual + audited)
- Physical infrastructure
- Emergency break-glass access

---

## 3. Git as the Source of Truth

### 3.1 Authoritative State

For Samakia Fabric:

| Component | Source of Truth |
|---------|----------------|
| Infrastructure | Terraform code |
| OS policy | Ansible code |
| Base images | Packer definitions |
| Decisions | `DECISIONS.md` |
| Operations | `OPERATIONS.md` |

If reality diverges from Git, **Git wins**.

---

### 3.2 Manual Changes

Manual changes:
- Are allowed only as emergency actions
- Must be documented
- Must be reconciled back into code

Unreconciled manual changes are considered **drift**.

---

## 4. GitOps vs Traditional Automation

Samakia Fabric explicitly rejects:
- ClickOps
- Long-lived manual configuration
- “Just SSH and fix it” workflows

Instead, it favors:
- Declarative intent
- Reviewable changes
- Rebuild-over-repair

---

## 5. Terraform and GitOps

Terraform is the **primary GitOps engine** for infrastructure.

Rules:
- Terraform is executed only from `envs/*`
- Plans must be reviewed before apply
- State is authoritative and protected
- Drift is corrected via re-apply or rebuild

Terraform does **not**:
- Provision OS users
- Configure applications
- Perform ad-hoc fixes

---

## 6. Ansible and GitOps

Ansible represents **desired OS state**, not imperative scripts.

GitOps expectations:
- Playbooks are idempotent
- Roles encode policy, not one-off tasks
- Inventory is generated, not handwritten
- Re-running Ansible is safe

Ansible complements Terraform, it does not replace it.

---

## 7. Golden Images and GitOps

Golden images are part of GitOps because:

- Their build definitions live in Git
- Their outputs are versioned
- Their usage is explicit in Terraform

Images are **immutable artifacts**.
Changing behavior requires a new version.

---

## 8. Environments and Promotion

Samakia Fabric encourages **environment separation**:

```text
envs/
├── dev
├── staging
└── prod
```

GitOps flow:
1. Change proposed in Git
2. Reviewed
3. Applied to lower environment
4. Promoted upward via Git history

There is no “hotfix directly to prod”.

---

## 9. CI/CD and GitOps (Future)

CI/CD is an **enabler**, not a requirement.

Planned GitOps enhancements:
- Terraform plan in CI
- Policy checks
- Read-only validation pipelines
- Controlled auto-apply for non-prod

Automation must never bypass human intent.

---

## 10. GitOps and Security

GitOps improves security by:
- Eliminating undocumented changes
- Providing audit trails
- Reducing standing privileges
- Enforcing least privilege through code

However:
- GitOps does not remove the need for access controls
- Secrets must still be managed securely

---

## 11. GitOps Failure Modes

Common anti-patterns (explicitly avoided):

- Treating GitOps as “auto-apply everything”
- Mixing provisioning and infrastructure
- Allowing tools to mutate state silently
- Using Git as a backup instead of authority

GitOps must **fail loudly**, not silently.

---

## 12. GitOps and AI Agents

Samakia Fabric is GitOps-friendly by design.

For AI agents:
- Git is the only interface
- Changes are proposed, not executed blindly
- Decisions and constraints are documented
- Actions are reviewable and reversible

This makes safe AI-assisted operations possible.

---

## 13. Summary

In Samakia Fabric:

- GitOps is about **control**, not speed
- Git is the source of truth
- Code defines intent
- Rebuild is preferred over repair
- Humans and AI operate under the same rules

If a change cannot be expressed safely in Git,
it does not belong in the system.
