# 📘 LXC Container Module (Proxmox VE 9 – v1)

This Terraform module provisions LXC containers on Proxmox VE 9 using an
existing, pre-built template.

It is designed as part of the Samakia Fabric infrastructure and follows
strict separation of responsibilities between Terraform, Packer, and Ansible.

## 🎯 Scope & Responsibilities

### What this module DOES

- Create and destroy LXC containers

- Attach containers to explicit storage (no implicit defaults)

- Configure CPU, memory, swap, and root filesystem size

- Attach a single network interface (DHCP)

- Inject SSH public keys via cloud-init

- Apply Proxmox tags

- Work reliably with disabled local storage

- Be safe for Proxmox VE 9

### What this module DOES NOT do (by design)

- Upload or manage templates

- Configure users, packages, or services

- Perform OS hardening

- Manage HA or Proxmox clusters

- Allocate IPs or manage DNS

- Manage LXC feature flags

- Act as a Proxmox control plane

Terraform is used only for lifecycle management.
Configuration management is handled by Ansible.

## 🧱 Architecture Assumptions

This module assumes the following pipeline:

```
Packer
  ↓
Golden LXC template (storage:vztmpl/file.tar.gz)
  ↓
Terraform (this module)
  ↓
LXC container
  ↓
Ansible
```

### Template requirements

- Template must already exist in Proxmox storage

Format must be:

```
<storage>:vztmpl/<file.tar.gz>
```

- Terraform will fail if the template is missing

## 🔒 Proxmox VE 9 Compatibility

This module includes explicit guards for known Proxmox 9 behaviors:

- No implicit local storage usage

- Explicit rootfs block is mandatory

- No HA flags (schema/API changes in PVE 9)

- Drift protection via lifecycle.ignore_changes

- No deprecated pveam or upload logic

It is tested and designed to work with:

- Proxmox VE 9.x

- Directory / NFS-backed storage

- Disabled local storage

## 📦 Module Interface (v1 – Frozen)

### Required inputs

- vmid

- hostname

- node

- template

- storage

- bridge

- ssh_public_keys

### Optional inputs

- cores (default: 1)

- memory (default: 512 MB)

- swap (default: 512 MB)

- rootfs_size (default: 16 GB)

- mac_address (default: null)

- tags (default: [])

- unprivileged (default: true)

### Outputs

- vmid

- hostname

- node

## API stability guarantee

Variable names and outputs are stable within v1.x.
If a small, optional input is added in a v1.x patch to fix a real operational
gap (e.g., deterministic connectivity), it will be documented and treated as
part of the stable v1.x contract from that release onward.

## 🧪 Example Usage

```hcl
module "app" {
  source = "../../modules/lxc-container"

  vmid     = 1200
  hostname = "app-1"
  node     = "proxmox1"

  template = "pve-nfs:vztmpl/ubuntu-24.04-lxc-rootfs.tar.gz"
  storage  = "pve-nfs"
  bridge   = "vmbr0"

  cores        = 2
  memory       = 2048
  rootfs_size  = 20

  ssh_public_keys = [
    file("~/.ssh/id_rsa.pub")
  ]

  tags = ["fabric", "app", "prod"]
}
```

## 🔁 Relationship with Ansible

This module intentionally exposes only:

- stable identifiers (vmid, hostname, node)

Dynamic data (IPs, facts, services) should be resolved by:

- Ansible dynamic inventory

- SSH-based discovery

- Proxmox tags

## 🚧 Non-Goals (Explicit)

The following are intentionally excluded:

- Kubernetes inside LXC

- Nested containers

- Multi-NIC networking

- IPAM

- Firewall rules

- Backup policies

These concerns belong to other layers of the platform.

## 🏷️ Versioning Policy

- v1.x: LXC lifecycle only (this module)

- v2.x: Optional extensions (multiple NICs, metadata outputs)

- Breaking changes only on major version bumps

## 📄 License & Contribution

This module is part of the Samakia Fabric project and is provided
to the community as an open infrastructure building block.

Contributions are welcome, provided they:

Respect the separation of concerns

Do not introduce implicit behavior

Remain compatible with Proxmox VE 9
