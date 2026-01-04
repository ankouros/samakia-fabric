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

Create a dedicated role for Terraform with **least-privilege**, but sufficient for:
- LXC lifecycle (create/config/start/stop)
- Storage allocation (templates + rootfs volumes)
- SDN plane creation/validation (for the shared plane `zshared/vshared`)
- Read-only inspection needed for inventory + acceptance (e.g., tag reads)

This role is designed to be **Proxmox 9 safe** and aligned with Samakia Fabric’s contracts:
- API token auth (no root@pam)
- strict TLS (no insecure flags)
- IaC-managed SDN primitives (requires SDN privileges)

Create the role:

```bash
# NOTE: privileges MUST be comma-separated (otherwise Proxmox concatenates the lines).
pveum role add TerraformProv -privs "\
Datastore.AllocateSpace,\
Datastore.AllocateTemplate,\
Datastore.Audit,\
Pool.Allocate,\
Pool.Audit,\
Sys.Audit,\
Sys.Console,\
Sys.Modify,\
VM.Allocate,\
VM.Audit,\
VM.Clone,\
VM.Config.CDROM,\
VM.Config.Cloudinit,\
VM.Config.CPU,\
VM.Config.Disk,\
VM.Config.HWType,\
VM.Config.Memory,\
VM.Config.Network,\
VM.Config.Options,\
VM.Migrate,\
VM.PowerMgmt,\
SDN.Audit,\
SDN.Allocate,\
SDN.Use\
"
```

Do not grant `Administrator`.

Notes:
- The `telmate/proxmox` provider enforces a permission pre-check and requires:
  - `Sys.Console`
  - `Sys.Modify`
  even if your Terraform does not explicitly use console actions.
- `SDN.Allocate` is required for **one-command** shared-plane bootstrap because Samakia Fabric creates/ensures SDN objects via `/cluster/sdn/*`.
- If you intentionally want a Terraform token that cannot create SDN:
  - you must pre-create the shared SDN plane (`zshared/vshared`) using an operator account that has `SDN.Allocate`, and
  - the Terraform token still needs `SDN.Audit` to validate/read SDN primitives.

If the user/role already exists and you need to update privileges:

```bash
pveum role modify TerraformProv -privs "\
Datastore.AllocateSpace,\
Datastore.AllocateTemplate,\
Datastore.Audit,\
Pool.Allocate,\
Pool.Audit,\
Sys.Audit,\
Sys.Console,\
Sys.Modify,\
VM.Allocate,\
VM.Audit,\
VM.Clone,\
VM.Config.CDROM,\
VM.Config.Cloudinit,\
VM.Config.CPU,\
VM.Config.Disk,\
VM.Config.HWType,\
VM.Config.Memory,\
VM.Config.Network,\
VM.Config.Options,\
VM.Migrate,\
VM.PowerMgmt,\
SDN.Audit,\
SDN.Allocate,\
SDN.Use\
"
```

---

## Create Terraform User

```bash
pveum user add terraform-prov@pve
```

You do not need a password for Terraform if you only use API tokens.
If you want GUI login for this user, you may set a password separately.

---

## Assign ACLs (recommended: scoped, not global)

For a minimal blast radius, prefer ACLs on the specific paths Terraform needs.

Example (cluster-wide, but scoped by object type):

```bash
# LXC/VM lifecycle + config
pveum aclmod /vms -user terraform-prov@pve -role TerraformProv

# Storage used for rootfs and templates (adjust storage name)
pveum aclmod /storage/pve-nfs -user terraform-prov@pve -role TerraformProv

# SDN plane management (required for shared-plane automation)
pveum aclmod /sdn -user terraform-prov@pve -role TerraformProv
```

Important (Proxmox provider pre-check):
- `Sys.Console` and `Sys.Modify` are Proxmox “system” privileges and are evaluated at broader scope.
- If Terraform still reports missing `Sys.*` privileges after you add them to the role, attach the role at `/` for the **token** (especially with `privsep=1`), or create a dedicated sys-only role and bind that at `/`.

If you explicitly want to grant the role globally (simpler, less safe):

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

SDN note (Samakia Fabric usage):
- Internal shared services attach to the shared SDN plane:
  - `zshared` / `vshared` (VLAN120, `10.10.120.0/24`)
- Legacy service-specific planes (`zonedns`/`vlandns`, `zminio`/`vminio`) are migration-only and must not be extended.
- If your Terraform token lacks `SDN.Allocate`, you must pre-create the shared SDN objects manually (then automation will validate and proceed).
- Proxmox SDN changes are **not active until applied** cluster-wide. Equivalent operator action:
  - `pvesh set /cluster/sdn`
  - Samakia Fabric automation performs this apply step when it creates/updates SDN primitives.

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
