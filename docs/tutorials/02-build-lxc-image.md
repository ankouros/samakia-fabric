# Tutorial 02 – Build LXC Golden Image with Packer

This tutorial describes how to build a **golden LXC image**
for use with Samakia Fabric using **Packer**.

Golden images are the foundation of:
- Immutability
- Security
- Reproducibility
- Reliable automation

---

## Scope

This tutorial covers:
- Image build philosophy
- Packer configuration for LXC images
- OS hardening basics
- SSH baseline behavior
- Exporting a Proxmox-compatible LXC rootfs

This tutorial does NOT cover:
- Terraform deployment
- Ansible configuration
- Application installation

---

## Image Philosophy

A golden image must:
- Be immutable after build
- Contain no environment-specific data
- Boot correctly as an LXC container
- Allow key-based SSH access for bootstrap
- Be safe to destroy and recreate

Images are **templates**, not servers.

---

## Tooling Requirements

On the build machine:
- Linux host
- Docker
- Packer 1.9+

Verify:

```bash
packer version
docker version
```

---

## Directory Structure

Samakia Fabric image builds live under:

```text
fabric-core/packer/lxc/ubuntu-24.04/
├── packer.pkr.hcl
├── provision.sh
├── cleanup.sh
└── README.md
```

Each image version is **artifact-driven** (monotonic, immutable) and then pinned in Git during promotion.

---

## Packer Source Strategy

Samakia Fabric uses:
- Docker as a build sandbox
- Ubuntu official base images
- Filesystem export for LXC

This avoids:
- VM builds
- Nested virtualization
- Proxmox-specific coupling

---

## Provisioning Script Responsibilities

`provision.sh` must:
- Update the package index
- Install minimal required packages
- Enable SSH
- Disable password authentication
- Perform baseline hardening

`provision.sh` must NOT:
- Create users
- Inject SSH keys
- Add environment-specific configuration

Required outcomes after provisioning:
- SSH daemon present
- Password login disabled
- Root login allowed only via keys (temporary bootstrap)

---

## User and SSH Model (Mandatory)

Golden images are **userless** by design.

Bootstrap flow:
1. Terraform injects a temporary SSH key for root
2. Ansible creates the non-root operator user
3. Ansible disables root SSH access

Do not bake users or keys into the image.

---

## Cleanup Script Responsibilities

`cleanup.sh` must:
- Remove SSH host keys
- Reset machine-id
- Clean package caches
- Remove temporary files

This ensures:
- Unique identity per container
- No clone collisions
- Predictable behavior

---

## Exporting the Root Filesystem

The final artifact must be a gzip-compressed tarball:

```text
ubuntu-24.04-lxc-rootfs-vX.tar.gz
```

Requirements:
- Standard GNU tar format
- Gzip compression
- Root filesystem at archive root

Proxmox expects `tar.gz`.

---

## Running the Build

Preferred (artifact-driven monotonic versions; no repo edits per version):

```bash
make image.build-next
```

Successful output produces:

```text
ubuntu-24.04-lxc-rootfs-v<N>.tar.gz
```

---

## Verify the Artifact

Before uploading to Proxmox:

```bash
tar tzf fabric-core/packer/lxc/ubuntu-24.04/ubuntu-24.04-lxc-rootfs-v<N>.tar.gz | head
```

You should see:

```text
bin/
etc/
usr/
var/
```

If not, stop.

---

## Uploading to Proxmox

Preferred: upload via Proxmox API token (no SSH/root on the node required):

```bash
export PM_API_URL="https://proxmox1:8006/api2/json"
export PM_API_TOKEN_ID="terraform-prov@pve!fabric-token"
export PM_API_TOKEN_SECRET="REDACTED"
export PM_NODE="proxmox1"
export PM_STORAGE="pve-nfs"

bash fabric-core/packer/lxc/scripts/upload-lxc-template-via-api.sh \
  fabric-core/packer/lxc/ubuntu-24.04/ubuntu-24.04-lxc-rootfs-v<N>.tar.gz
```

Forbidden:
- Manual Proxmox node shell uploads (SSH/SCP/root on Proxmox nodes is out of contract).

---

## Versioning Strategy

- Every image change increments the version
- Old images are retained
- Terraform references images explicitly

Never overwrite an existing image.

---

## Common Failure Modes

| Problem               | Cause                             |
|-----------------------|------------------------------------|
| SSH access denied     | Root SSH disabled or key missing   |
| Proxmox import failure| Invalid tar format                 |
| Duplicate identities  | `machine-id` not reset             |
| Drift                 | Manual changes after build         |

All are image-level problems.

---

## Security Notes

- Images contain no secrets
- Credentials are injected at deploy time
- Compromised images are rebuilt, not fixed
- Image rebuild is the only safe fix

---

## What's Next

Proceed to:
- `docs/tutorials/03-deploy-lxc-with-terraform.md`
