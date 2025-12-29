# Samakia Fabric – Promotion Flow (Image → Template → Environment)

This document defines the **only supported, production-safe upgrade path**:

Packer image artifact (`ubuntu-24.04-lxc-rootfs-vN.tar.gz`)
→ Proxmox template storage entry (`<storage>:vztmpl/ubuntu-24.04-lxc-rootfs-vN.tar.gz`)
→ Terraform environment pin (`local.lxc_rootfs_version = "vN"`)

Promotion is **explicit** and **Git-driven**. Rollback is a **normal operation**.

---

## 1) Versioning policy (immutable contract)

- Every image artifact is **monotonic** and **immutable**: `...-v5.tar.gz`, `...-v6.tar.gz`, …
- Images/templates are **never overwritten**.
- Old versions remain available for **rollback**.
- “Latest” semantics are forbidden by design.

When to bump the version:
- Any change to the image build (packages, SSH baseline, hardening defaults, cleanup behavior).
- Any change that could affect bootstrap/hardening behavior.

Why prod promotion is forbidden without a Git change:
- Prod must never “drift” into a new image version through implicit behavior or local operator state.

---

## 2) Template upload & registration (API-based, idempotent)

This runs on the **runner host** (your workstation / CI runner) that already trusts the Proxmox internal CA.

### Required inputs

- `PM_API_URL` (e.g. `https://proxmox1:8006/api2/json`)
- `PM_API_TOKEN_ID`
- `PM_API_TOKEN_SECRET`
- `PM_NODE` (default `proxmox1`)
- `PM_STORAGE` (default `pve-nfs`)

### Upload procedure

1) Build a new image artifact (monotonic auto-bump; example outcome: `v6`):

```bash
make image.build-next
```

2) Upload the artifact to Proxmox storage as an LXC template:

```bash
bash fabric-core/packer/lxc/scripts/upload-lxc-template-via-api.sh \
  fabric-core/packer/lxc/ubuntu-24.04/ubuntu-24.04-lxc-rootfs-v<N>.tar.gz
```

### Success / failure rules

- Success = script exits `0` and reports: `<storage>:vztmpl/<filename>`.
- Failure = script exits non-zero and prints a specific error:
  - template already exists (immutable rule)
  - TLS trust missing / API not reachable
  - authentication/authorization failure
  - malformed artifact name (must be `*-v<monotonic>.tar.gz`)

---

## 3) Environment wiring (Terraform pinning)

Each environment pins a **single version string in Git**:

- `fabric-core/terraform/envs/samakia-dev/main.tf`: `local.lxc_rootfs_version = "vN"`
- `fabric-core/terraform/envs/samakia-prod/main.tf`: `local.lxc_rootfs_version = "vN"`

Changing the version:
- is **expected** to trigger **destroy/recreate**
- is the **only supported upgrade/rollback mechanism**

Terraform also sets deterministic Proxmox UI tags on each LXC:

- `golden-vN;plane-<plane>;env-<env>;role-<role>`

When you promote/rollback by changing the pinned template version, the recreated containers will also carry the updated `golden-vN` tag automatically.

---

## 4) Promotion mechanics (GitOps-style)

Promotion is a Git change:

1) Dev can advance first:
   - update `fabric-core/terraform/envs/samakia-dev/main.tf` to `v6`
   - apply in dev, validate bootstrap + harden + smoke checks

2) Promotion to prod is a deliberate change:
   - open PR / request review
   - update `fabric-core/terraform/envs/samakia-prod/main.tf` from `v5` → `v6`
   - apply in prod, then bootstrap + harden

Recommended operator rule:
- One image version per promotion PR.
- Require at least one reviewer for prod promotions.

---

## 5) Rollback procedure (first-class)

Rollback is not “surgery”. It is the same flow in reverse:

1) Revert the Git change (or change `local.lxc_rootfs_version` back to the previous value).
2) Apply Terraform (expected destroy/recreate).
3) Run phase 1 bootstrap for the new container:
   - `ansible-playbook fabric-core/ansible/playbooks/bootstrap.yml`
4) Run phase 2 hardening:
   - `ansible-playbook fabric-core/ansible/playbooks/harden.yml`
5) Validate SSH:
   - `ssh samakia@<ip>` must succeed
   - `ssh root@<ip>` must fail

No manual container edits. No in-place mutations.

---

## 6) Validation & safety checks (post-apply)

After `terraform apply` (dev or prod):

1) Confirm CT exists and is running (Proxmox UI / node shell).
2) Resolve `<ip>` (no DNS):
   - Proxmox UI Console: `ip -4 a`
3) Run Ansible:
   - `bootstrap.yml` (only for newly created containers)
   - `harden.yml`
4) Smoke checks:
   - `ssh samakia@<ip> true`
   - `ssh root@<ip> true` must fail

If anything fails:
- do not “fix” inside the container manually
- use rollback or rebuild the image and promote again
