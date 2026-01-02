###############################################################################
# Samakia Fabric – Shared Control Plane Services (Phase 2.1)
###############################################################################

locals {
  ###########################################################################
  # Promotion contract: pinned template version (no "latest")
  ###########################################################################
  lxc_rootfs_version = "v4"
  lxc_template       = "pve-nfs:vztmpl/ubuntu-24.04-lxc-rootfs-${local.lxc_rootfs_version}.tar.gz"

  ###########################################################################
  # Proxmox UI tags (deterministic; Terraform is source of truth)
  ###########################################################################
  tag_env   = "infra"
  tag_plane = "shared"
  tag_golden = try(
    regex("-(v[0-9]+)\\.tar\\.gz$", local.lxc_template)[0],
    null,
  )

  ###########################################################################
  # Network contracts (explicit)
  ###########################################################################
  lan_cidr      = "192.168.11.0/24"
  lan_gateway   = "192.168.11.1"
  lan_bridge    = "vmbr0"
  ntp_lan_vip   = "192.168.11.120"
  vault_lan_vip = "192.168.11.121"
  obs_lan_vip   = "192.168.11.122"

  vlan_id     = 120
  vlan_zone   = "zshared"
  vlan_vnet   = "vshared"
  vlan_cidr   = "10.10.120.0/24"
  vlan_gw_vip = "10.10.120.1"
}

check "template_version_pinned" {
  assert {
    condition     = can(regex("^v[0-9]+$", local.lxc_rootfs_version))
    error_message = "Shared env template version must be pinned to a monotonic value like 'v6' (no 'latest', no implicit upgrades)."
  }

  assert {
    condition     = can(regex("-v[0-9]+\\.tar\\.gz$", local.lxc_template))
    error_message = "Shared env template filename must be versioned and immutable (expected '*-v<monotonic>.tar.gz')."
  }
}

check "tag_schema" {
  assert {
    condition     = local.tag_golden != null && can(regex("^v[0-9]+$", local.tag_golden))
    error_message = "Shared env could not derive golden image version from local.lxc_template (expected '*-v<N>.tar.gz' so tags can include 'golden-vN')."
  }

  assert {
    condition     = can(regex("^[a-z0-9_-]+$", local.tag_env)) && can(regex("^[a-z0-9_-]+$", local.tag_plane))
    error_message = "Shared env tag values must match ^[a-z0-9_-]+$ for Proxmox UI compatibility."
  }
}

###############################################################################
# Proxmox SDN prerequisites (shared services VLAN plane)
###############################################################################

resource "null_resource" "sdn_shared_plane" {
  triggers = {
    zone   = local.vlan_zone
    vnet   = local.vlan_vnet
    vlan   = tostring(local.vlan_id)
    subnet = local.vlan_cidr
    gw     = local.vlan_gw_vip
  }

  provisioner "local-exec" {
    command = "bash \"${var.fabric_repo_root}/ops/scripts/proxmox-sdn-ensure-shared-plane.sh\" --apply"
  }
}

###############################################################################
# LXC containers
###############################################################################

resource "proxmox_lxc" "ntp_1" {
  depends_on = [null_resource.sdn_shared_plane]

  vmid        = 3301
  hostname    = "ntp-1"
  target_node = "proxmox1"

  ostemplate = local.lxc_template
  ostype     = "ubuntu"

  unprivileged = true
  onboot       = true
  start        = true

  cores  = 2
  memory = 1024
  swap   = 512

  rootfs {
    storage = "pve-nfs"
    size    = "8G"
  }

  # LAN (mgmt + VIP holder)
  network {
    name   = "eth0"
    bridge = local.lan_bridge
    hwaddr = "BC:24:11:AD:60:A1"
    ip     = "192.168.11.106/24"
    gw     = local.lan_gateway
  }

  # VLAN120 (shared plane gateway VIP holder)
  network {
    name   = "eth1"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:60:A2"
    ip     = "10.10.120.11/24"
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)

  tags = "golden-${local.tag_golden};plane-${local.tag_plane};env-${local.tag_env};role-edge"

  lifecycle {
    ignore_changes = [
      network,
      features,
    ]
  }
}

resource "proxmox_lxc" "ntp_2" {
  depends_on = [null_resource.sdn_shared_plane]

  vmid        = 3302
  hostname    = "ntp-2"
  target_node = "proxmox2"

  ostemplate = local.lxc_template
  ostype     = "ubuntu"

  unprivileged = true
  onboot       = true
  start        = true

  cores  = 2
  memory = 1024
  swap   = 512

  rootfs {
    storage = "pve-nfs"
    size    = "8G"
  }

  # LAN (mgmt + VIP holder)
  network {
    name   = "eth0"
    bridge = local.lan_bridge
    hwaddr = "BC:24:11:AD:60:B1"
    ip     = "192.168.11.107/24"
    gw     = local.lan_gateway
  }

  # VLAN120 (shared plane gateway VIP holder)
  network {
    name   = "eth1"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:60:B2"
    ip     = "10.10.120.12/24"
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)

  tags = "golden-${local.tag_golden};plane-${local.tag_plane};env-${local.tag_env};role-edge"

  lifecycle {
    ignore_changes = [
      network,
      features,
    ]
  }
}

resource "proxmox_lxc" "vault_1" {
  depends_on = [null_resource.sdn_shared_plane]

  vmid        = 3303
  hostname    = "vault-1"
  target_node = "proxmox3"

  ostemplate = local.lxc_template
  ostype     = "ubuntu"

  unprivileged = true
  onboot       = true
  start        = true

  cores  = 2
  memory = 2048
  swap   = 512

  rootfs {
    storage = "pve-nfs"
    size    = "12G"
  }

  network {
    name   = "eth0"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:60:C1"
    ip     = "10.10.120.21/24"
    gw     = local.vlan_gw_vip
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)

  tags = "golden-${local.tag_golden};plane-${local.tag_plane};env-${local.tag_env};role-vault"

  lifecycle {
    ignore_changes = [
      network,
      features,
    ]
  }
}

resource "proxmox_lxc" "vault_2" {
  depends_on = [null_resource.sdn_shared_plane]

  vmid        = 3304
  hostname    = "vault-2"
  target_node = "proxmox1"

  ostemplate = local.lxc_template
  ostype     = "ubuntu"

  unprivileged = true
  onboot       = true
  start        = true

  cores  = 2
  memory = 2048
  swap   = 512

  rootfs {
    storage = "pve-nfs"
    size    = "12G"
  }

  network {
    name   = "eth0"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:60:D1"
    ip     = "10.10.120.22/24"
    gw     = local.vlan_gw_vip
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)

  tags = "golden-${local.tag_golden};plane-${local.tag_plane};env-${local.tag_env};role-vault"

  lifecycle {
    ignore_changes = [
      network,
      features,
    ]
  }
}

resource "proxmox_lxc" "obs_1" {
  depends_on = [null_resource.sdn_shared_plane]

  vmid        = 3305
  hostname    = "obs-1"
  target_node = "proxmox2"

  ostemplate = local.lxc_template
  ostype     = "ubuntu"

  unprivileged = true
  onboot       = true
  start        = true

  cores  = 2
  memory = 2048
  swap   = 512

  rootfs {
    storage = "pve-nfs"
    size    = "16G"
  }

  network {
    name   = "eth0"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:60:E1"
    ip     = "10.10.120.31/24"
    gw     = local.vlan_gw_vip
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)

  tags = "golden-${local.tag_golden};plane-${local.tag_plane};env-${local.tag_env};role-obs"

  lifecycle {
    ignore_changes = [
      network,
      features,
    ]
  }
}

resource "proxmox_lxc" "obs_2" {
  depends_on = [null_resource.sdn_shared_plane]

  vmid        = 3306
  hostname    = "obs-2"
  target_node = "proxmox3"

  ostemplate = local.lxc_template
  ostype     = "ubuntu"

  unprivileged = true
  onboot       = true
  start        = true

  cores  = 2
  memory = 2048
  swap   = 512

  rootfs {
    storage = "pve-nfs"
    size    = "16G"
  }

  network {
    name   = "eth0"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:60:E2"
    ip     = "10.10.120.32/24"
    gw     = local.vlan_gw_vip
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)

  tags = "golden-${local.tag_golden};plane-${local.tag_plane};env-${local.tag_env};role-obs"

  lifecycle {
    ignore_changes = [
      network,
      features,
    ]
  }
}

###############################################################################
# Outputs for Ansible inventory + acceptance
###############################################################################

output "lxc_inventory" {
  description = "Inventory data for Ansible"
  value = {
    ntp_1 = {
      hostname = proxmox_lxc.ntp_1.hostname
      node     = proxmox_lxc.ntp_1.target_node
      vmid     = proxmox_lxc.ntp_1.vmid
    }
    ntp_2 = {
      hostname = proxmox_lxc.ntp_2.hostname
      node     = proxmox_lxc.ntp_2.target_node
      vmid     = proxmox_lxc.ntp_2.vmid
    }
    vault_1 = {
      hostname = proxmox_lxc.vault_1.hostname
      node     = proxmox_lxc.vault_1.target_node
      vmid     = proxmox_lxc.vault_1.vmid
    }
    vault_2 = {
      hostname = proxmox_lxc.vault_2.hostname
      node     = proxmox_lxc.vault_2.target_node
      vmid     = proxmox_lxc.vault_2.vmid
    }
    obs_1 = {
      hostname = proxmox_lxc.obs_1.hostname
      node     = proxmox_lxc.obs_1.target_node
      vmid     = proxmox_lxc.obs_1.vmid
    }
    obs_2 = {
      hostname = proxmox_lxc.obs_2.hostname
      node     = proxmox_lxc.obs_2.target_node
      vmid     = proxmox_lxc.obs_2.vmid
    }
  }
}

output "shared_endpoints" {
  description = "Shared services VIPs and node IPs"
  value = {
    ntp_vip     = local.ntp_lan_vip
    vault_vip   = local.vault_lan_vip
    obs_vip     = local.obs_lan_vip
    vlan_gw_vip = local.vlan_gw_vip
    ntp_edges = {
      ntp_1 = { lan_ip = "192.168.11.106", vlan_ip = "10.10.120.11" }
      ntp_2 = { lan_ip = "192.168.11.107", vlan_ip = "10.10.120.12" }
    }
    vault_nodes = [
      "10.10.120.21",
      "10.10.120.22",
    ]
    obs_nodes = [
      "10.10.120.31",
      "10.10.120.32",
    ]
  }
}
