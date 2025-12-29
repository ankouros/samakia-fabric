###############################################################################
# Samakia Fabric – Staging LXC
###############################################################################

locals {
  # Promotion contract:
  # - this value is pinned in Git (no "latest")
  # - changing it is the only supported upgrade/rollback path (destroy/recreate)
  lxc_rootfs_version = "v4"
  lxc_template       = "pve-nfs:vztmpl/ubuntu-24.04-lxc-rootfs-${local.lxc_rootfs_version}.tar.gz"
}

check "template_version_pinned" {
  assert {
    condition     = can(regex("^v[0-9]+$", local.lxc_rootfs_version))
    error_message = "Staging template version must be pinned to a monotonic value like 'v5' (no 'latest', no implicit upgrades)."
  }

  assert {
    condition     = can(regex("-v[0-9]+\\.tar\\.gz$", local.lxc_template))
    error_message = "Staging template filename must be versioned and immutable (expected '*-v<monotonic>.tar.gz')."
  }
}

module "monitoring_1" {
  source = "../../modules/lxc-container"

  ###########################################################################
  # Identity
  ###########################################################################
  vmid     = 2100
  hostname = "monitoring-staging-1"
  node     = "proxmox1"

  ###########################################################################
  # Template & storage
  ###########################################################################
  template    = local.lxc_template
  storage     = "pve-nfs"
  bridge      = "vmbr0"
  mac_address = "BC:24:11:AD:49:E1"

  ###########################################################################
  # Resources
  ###########################################################################
  cores       = 2
  memory      = 2048
  swap        = 1024
  rootfs_size = 20

  ###########################################################################
  # Access
  ###########################################################################
  ssh_public_keys = var.ssh_public_keys

  ###########################################################################
  # Metadata
  ###########################################################################
  tag_env    = "staging"
  tag_plane  = "monitoring"
  tag_role   = "mon"
  tags_extra = []
}

###############################################################################
# Outputs for Ansible inventory
###############################################################################

output "lxc_inventory" {
  description = "Inventory data for Ansible"
  value = {
    monitoring_1 = {
      hostname = module.monitoring_1.hostname
      node     = module.monitoring_1.node
      vmid     = module.monitoring_1.vmid
    }
  }
}
