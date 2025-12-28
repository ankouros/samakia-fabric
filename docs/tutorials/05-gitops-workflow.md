# Tutorial 05 – GitOps Workflow in Samakia Fabric

This tutorial defines the **GitOps workflow**
used to operate Samakia Fabric safely and predictably.

Git is not documentation.
Git is the **control plane**.

---

## 1. Scope

This tutorial covers:

- Git as the source of truth
- Change flow across Packer, Terraform, Ansible
- Review and approval model
- Rollback and recovery
- Day-2 operations

This tutorial does NOT cover:
- CI/CD tool specifics
- Application GitOps (e.g. Argo CD)
- Cloud provider workflows

---

## 2. GitOps Philosophy

In Samakia Fabric:

- Desired state lives in Git
- Reality is disposable
- Drift is resolved by rebuild

No change is valid unless it is committed.

---

## 3. Repository as Control Plane

The repository defines:

- Infrastructure intent (Terraform)
- Image baselines (Packer)
- Configuration policy (Ansible)
- Operational rules (docs)

If it is not in the repo,
it does not exist.

---

## 4. Branching Model (Recommended)

A simple, strict model is used:

- `main` → authoritative, production
- feature branches → proposed changes

No direct commits to `main`.

---

## 5. Change Categories

All changes fall into one of these categories:

### 5.1 Image Changes (Packer)

Examples:
- OS updates
- SSH hardening
- Base package changes

Workflow:
1. Modify image code
2. Build new image version
3. Commit image changes
4. Update Terraform reference

Images are immutable.
Old versions are retained.

---

### 5.2 Infrastructure Changes (Terraform)

Examples:
- New LXC containers
- Resource changes
- Network or storage updates

Workflow:
1. Modify Terraform code
2. Run `terraform plan`
3. Review plan
4. Apply after approval

Terraform plans are reviewed artifacts.

---

### 5.3 Configuration Changes (Ansible)

Examples:
- Security policies
- OS settings
- Runtime prerequisites

Workflow:
1. Modify playbooks/roles
2. Test against target hosts
3. Commit changes
4. Re-run idempotently

Ansible enforces policy, not identity.

---

## 6. Pull Request Flow

Every change must go through a PR.

A valid PR includes:
- Clear description
- Scope of impact
- Rollback plan (if applicable)

PRs are rejected if:
- They introduce manual steps
- They bypass immutability
- They blur responsibility boundaries

---

## 7. Review Checklist

Reviewers must verify:

- Change matches declared intent
- No secrets are introduced
- No manual state is assumed
- Replacement semantics are understood

If reviewers cannot explain the change,
it is rejected.

---

## 8. Applying Changes

Changes are applied in this order:

1. Images (Packer)
2. Infrastructure (Terraform)
3. Configuration (Ansible)

Never reverse this order.

---

## 9. Rollback Strategy

### Image Rollback

- Revert Terraform image reference
- Apply Terraform
- Container is replaced

Rollback is deterministic.

---

### Infrastructure Rollback

- Revert Terraform code
- Apply
- Resources are reconciled

State files remain authoritative.

---

### Configuration Rollback

- Revert Ansible changes
- Re-run playbooks

Idempotency guarantees safety.

---

## 10. Drift Handling

Drift sources:
- Manual Proxmox UI changes
- SSH hotfixes
- Emergency edits

Resolution:
- Identify drift
- Remove manual changes
- Re-apply from Git
- Replace if necessary

Drift is treated as an incident.

---

## 11. Day-2 Operations

Allowed day-2 actions:
- Scaling by code
- Replacing containers
- Updating images
- Adjusting configuration

Forbidden day-2 actions:
- Manual mutation
- Ad-hoc fixes
- UI-only changes

Operations are code-driven.

---

## 12. Incident Response in GitOps

During incidents:
- Temporary manual actions may occur
- Actions must be documented
- Git must be reconciled immediately after

Permanent fixes always go to Git.

---

## 13. GitOps and HA

GitOps supports HA by:
- Making recovery predictable
- Enabling fast rebuilds
- Reducing human error

GitOps does not replace HA mechanisms.
It enables their correct use.

---

## 14. GitOps and Security

Security relies on GitOps to:
- Track changes
- Audit actions
- Rebuild compromised systems

Secrets never live in Git.
Only references do.

---

## 15. Anti-Patterns (Explicitly Rejected)

- “Quick fixes” outside Git
- Emergency changes never reconciled
- Terraform apply without review
- Ansible as a repair tool

These destroy trust in the system.

---

## 16. GitOps and AI Agents

AI agents must:
- Propose changes via PRs
- Never apply directly
- Operate within documented boundaries

AI without GitOps guardrails is unsafe.

---

## 17. Validation Checklist

Before merging:
- [ ] Code reviewed
- [ ] Plan reviewed
- [ ] Rollback understood
- [ ] No secrets introduced

If unsure, do not merge.

---

## 18. Final Rule

If a change cannot be:
- Reviewed
- Reverted
- Rebuilt

It does not belong in Samakia Fabric.

Git defines intent.
Reality follows.
