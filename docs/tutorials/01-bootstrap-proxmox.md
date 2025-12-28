# Tutorial 01 – Bootstrap Proxmox for Samakia Fabric

This tutorial prepares a **clean Proxmox node or cluster**
to be safely managed by **Samakia Fabric**.

Do not skip steps. Do not improvise.
This tutorial establishes trust boundaries.

---

## Scope

This tutorial covers:
- Proxmox host preparation
- User and role creation for Terraform
- SSH hardening basics
- Storage and network assumptions
- Validation checklist

This tutorial does NOT cover:
- Cluster creation
- Ceph setup
- Application deployment

---

## Prerequisites

- Proxmox VE 8 or 9 installed
- Root access to Proxmox nodes
- Working network connectivity
- DNS or static IPs for nodes

All commands are executed **on Proxmox nodes** unless stated otherwise.

---

## Verify Proxmox Health

On each node:

```bash
pveversion
pvecm status || true
```

Ensure:
- Proxmox services are running
- Cluster quorum is healthy (if clustered)

If the cluster is not healthy, stop.

---

## Configure Hostname and DNS

Each Proxmox node must have:
- Stable hostname
- Working DNS resolution

Example `/etc/hosts`:

```text
192.168.11.90 proxmox1
192.168.11.91 proxmox2
192.168.11.92 proxmox3
```

Test:

```bash
hostname
ping -c 2 proxmox1
```

Terraform relies on API connectivity.

---

## Create Terraform Role (Proxmox 9 Safe)

Create a dedicated role with minimum required privileges:

```bash
pveum role add TerraformProv -privs "\
Datastore.AllocateSpace\
Datastore.AllocateTemplate\
Datastore.Audit\
Pool.Allocate\
Pool.Audit\
Sys.Audit\
Sys.Console\
Sys.Modify\
VM.Allocate\
VM.Audit\
VM.Clone\
VM.Config.CDROM\
VM.Config.Cloudinit\
VM.Config.CPU\
VM.Config.Disk\
VM.Config.HWType\
VM.Config.Memory\
VM.Config.Network\
VM.Config.Options\
VM.Migrate\
VM.PowerMgmt\
SDN.Use\
"
```

Do not grant `Administrator`.

---

## Create Terraform User

```bash
pveum user add terraform-prov@pve
pveum passwd terraform-prov@pve
```

Assign role globally:

```bash
pveum aclmod / -user terraform-prov@pve -role TerraformProv
```

Verify:

```bash
pveum user list | grep terraform
pveum acl list | grep terraform
```

---

## Optional: API Token Instead of Password

Recommended for production:

```bash
pveum user token add terraform-prov@pve fabric-token
```

Use the token in Terraform instead of a password.

Important:
- By default, Proxmox creates tokens with privilege separation enabled (`privsep=1`). These tokens do **not** inherit the user's ACLs.
- You must explicitly attach the role to the token:

```bash
pveum aclmod / -token 'terraform-prov@pve!fabric-token' -role TerraformProv
```

Alternative (less explicit):
- Create a token without privilege separation (`--privsep 0`) so it inherits the user ACLs.

---

## SSH Hardening (Baseline)

Ensure root login is key-based only. Edit `/etc/ssh/sshd_config`:

```text
PermitRootLogin prohibit-password
PasswordAuthentication no
UseDNS no
```

Restart SSH:

```bash
systemctl restart ssh
```

Do not lock yourself out.

---

## Storage Assumptions

Samakia Fabric assumes:
- A shared storage exists (e.g. `pve-nfs`)
- Storage supports `vztmpl` and `images`

Verify:

```bash
pvesm status
pvesm list pve-nfs
```

Local-only storage is not HA-safe.

---

## Network Assumptions

At minimum:
- One Linux bridge (e.g. `vmbr0`)
- DHCP or routable IPs

Verify:

```bash
ip link show vmbr0
```

Advanced SDN is optional and out of scope here.

---

## API Connectivity Test

From your workstation (or Terraform runner):

```bash
curl https://proxmox1:8006/api2/json
```

You should receive a JSON response.

---

## Final Validation Checklist

Before proceeding:
- Proxmox nodes reachable
- `terraform-prov@pve` exists
- Correct privileges assigned
- Storage available
- Network bridge exists
- SSH hardened

If any item fails, fix it now.

---

## What’s Next

After this tutorial:
- Build LXC golden images with Packer
- Deploy containers via Terraform
- Configure via Ansible
- Enable GitOps workflows

Proceed to:
- `docs/tutorials/02-build-lxc-image.md`

---

## Final Warning

Never mix:
- Manual Proxmox UI changes
- Terraform-managed resources

Terraform is the authority. If Terraform and reality diverge,
reconcile by rebuild.
