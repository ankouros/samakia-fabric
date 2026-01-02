# Tutorial 03 – Deploy LXC Containers with Terraform

This tutorial describes how to deploy **LXC containers on Proxmox**
using **Terraform**, following Samakia Fabric principles.

Terraform is the **authority for existence and placement**.
Manual creation is forbidden.

---

## Scope

This tutorial covers:
- Terraform environment structure
- Provider configuration for Proxmox
- Using LXC modules
- Deploying a production container
- Updating and replacing containers safely

This tutorial does NOT cover:
- Image building (see Tutorial 02)
- Configuration management (Ansible)
- Application deployment

---

## Terraform Philosophy in Fabric

Terraform is used to:
- Declare infrastructure intent
- Create, destroy, and replace resources
- Enforce immutability boundaries

Terraform is NOT used to:
- Patch running systems
- Manage applications
- Perform operational fixes

If Terraform cannot express it, it should not happen.

---

## Directory Structure

Terraform code is organized as:

```text
fabric-core/terraform/
├── envs/
│   └── samakia-prod/
│       ├── main.tf
│       ├── variables.tf
│       ├── provider.tf
│       ├── checks.tf
│       └── terraform.tfvars (local only)
├── modules/
│   └── lxc-container/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
```

Environments are isolated. Modules are reusable.

---

## Provider Configuration (Proxmox 9 Safe)

The Proxmox provider is configured once per environment.

Example `envs/<env>/provider.tf`:

```hcl
provider "proxmox" {
  pm_api_url      = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
}
```

Credentials are never hardcoded.
Use variables or environment injection.

Production guidance:
- Install the Proxmox CA in the runner trust store (no insecure flags)
- Prefer API tokens over passwords for Terraform automation

---

## Environment Variables

Example `terraform.tfvars.example` (copy to `terraform.tfvars` locally).

Token auth example:

```hcl
pm_api_url          = "https://proxmox1:8006/api2/json"
pm_api_token_id     = "terraform-prov@pve!fabric-token"
pm_api_token_secret = "REDACTED"
```

If you created the token with privilege separation (`privsep=1`), ensure you attached the ACL to the token in Proxmox:

```bash
pveum aclmod / -token 'terraform-prov@pve!fabric-token' -role TerraformProv
```

Password auth is supported only as a fallback (not recommended for automation).

Never commit secrets.

---

## LXC Module Usage

Each LXC container is declared via a module.

Example `main.tf`:

```hcl
module "monitoring_1" {
  source = "../../modules/lxc-container"

  vmid     = 1100
  hostname = "monitoring-1"
  node     = "proxmox1"

  template = "pve-nfs:vztmpl/ubuntu-24.04-lxc-rootfs-v3.tar.gz"
  storage  = "pve-nfs"
  bridge   = "vmbr0"

  cores       = 2
  memory      = 2048
  swap        = 1024
  rootfs_size = 20

  ssh_public_keys = [
    "ssh-ed25519 AAAA... samakia"
  ]

  tags = [
    "fabric",
    "monitoring",
    "prod"
  ]
}
```

Each container is explicit. Implicit behavior is forbidden.
These keys are used for temporary root bootstrap and must be rotated if exposed.

---

## Validate and Plan

Always run:

```bash
terraform fmt
terraform validate
terraform plan
```

Review the plan carefully. Terraform will tell you if replacement is required.

---

## Apply and Create the Container

```bash
terraform apply
```

Expected result:
- LXC container created
- DHCP or network assigned
- SSH keys injected
- Container started

Terraform output is the source of truth.

---

## Replacement Semantics

If you change:
- Image reference
- Root filesystem size
- Identity fields

Terraform will:
- Destroy the old container
- Create a new one

This is expected and desired.

---

## Handling Updates

Image update example:

```hcl
template = "pve-nfs:vztmpl/ubuntu-24.04-lxc-rootfs-v3.tar.gz"
```

to:

```hcl
template = "pve-nfs:vztmpl/ubuntu-24.04-lxc-rootfs-v3.tar.gz"
```

Then:

```bash
terraform plan
terraform apply
```

The container will be replaced.

---

## Proxmox 9 Guards

The LXC module includes:
- Explicit storage
- Feature flag protection
- Lifecycle ignore rules

These prevent:
- Unauthorized feature changes
- Provider drift
- Accidental privilege escalation

Never remove these guards lightly.

---

## Outputs for Downstream Automation

Terraform exports inventory data:

```hcl
output "lxc_inventory" {
  value = {
    monitoring_1 = {
      hostname = module.monitoring_1.hostname
      node     = module.monitoring_1.node
      vmid     = module.monitoring_1.vmid
    }
  }
}
```

This output feeds Ansible. Terraform → Ansible is a one-way flow.

---

## Validation on Proxmox

On the Proxmox node:

```bash
pct list
pct status 1100
pct exec 1100 -- hostname
```

Never modify containers via `pct set`.

---

## Common Failure Modes

| Problem            | Cause                                |
|--------------------|---------------------------------------|
| SSH denied         | Root SSH disabled or key missing      |
| 403 errors         | Insufficient Proxmox role             |
| Drift              | Manual Proxmox UI changes             |
| Unexpected replace | Identity change                        |

All must be fixed in code.

---

## Destruction Is Normal

Destroying containers is routine:

```bash
terraform destroy -target=module.monitoring_1
```

If destruction feels dangerous, immutability is not understood.

---

## What's Next

Proceed to:
- `docs/tutorials/04-bootstrap-with-ansible.md`
