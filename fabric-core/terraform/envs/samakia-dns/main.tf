###############################################################################
# Samakia Fabric – DNS infrastructure (infra.samakia.net)
###############################################################################

locals {
  ###########################################################################
  # Promotion contract: pinned template version (no "latest")
  ###########################################################################
  lxc_rootfs_version = "v4"
  lxc_template       = "pve-nfs:vztmpl/ubuntu-24.04-lxc-rootfs-${local.lxc_rootfs_version}.tar.gz"

  ###########################################################################
  # Network contracts (non-negotiable)
  ###########################################################################
  lan_cidr    = "192.168.11.0/24"
  lan_gateway = "192.168.11.1"
  lan_dns_vip = "192.168.11.100"
  lan_bridge  = "vmbr0"

  vlan_id     = 100
  vlan_zone   = "zonedns"
  vlan_vnet   = "vlandns"
  vlan_cidr   = "10.10.100.0/24"
  vlan_gw_vip = "10.10.100.1"

  tag_env   = "infra"
  tag_plane = "dns"
  golden    = regex("-(v[0-9]+)\\.tar\\.gz$", local.lxc_template)[0]
}

check "template_version_pinned" {
  assert {
    condition     = can(regex("^v[0-9]+$", local.lxc_rootfs_version))
    error_message = "DNS env template version must be pinned to a monotonic value like 'v6' (no 'latest', no implicit upgrades)."
  }

  assert {
    condition     = can(regex("-v[0-9]+\\.tar\\.gz$", local.lxc_template))
    error_message = "DNS env template filename must be versioned and immutable (expected '*-v<monotonic>.tar.gz')."
  }
}

check "tag_schema" {
  assert {
    condition     = can(regex("^v[0-9]+$", local.golden))
    error_message = "Failed to derive golden image version from template (expected vN): ${local.lxc_template}"
  }
}

###############################################################################
# Proxmox SDN prerequisites (DNS VLAN plane)
#
# Telmate provider lacks SDN primitives; ensure SDN via Proxmox HTTP API
# using token auth (create-once, validate shape, fail loud on mismatch).
###############################################################################

resource "null_resource" "sdn_dns_plane" {
  triggers = {
    zone   = local.vlan_zone
    vnet   = local.vlan_vnet
    vlan   = tostring(local.vlan_id)
    subnet = local.vlan_cidr
    gw     = local.vlan_gw_vip
  }

  provisioner "local-exec" {
    command = "bash \"${var.fabric_repo_root}/ops/scripts/proxmox-sdn-ensure-dns-plane.sh\" --apply"
  }
}

###############################################################################
# LXC containers
###############################################################################

resource "proxmox_lxc" "dns_edge_1" {
  depends_on = [null_resource.sdn_dns_plane]

  vmid        = 3101
  hostname    = "dns-edge-1"
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

  # LAN (management + VIP holder)
  network {
    name   = "eth0"
    bridge = local.lan_bridge
    hwaddr = "BC:24:11:AD:49:A1"
    ip     = "192.168.11.111/24"
    gw     = local.lan_gateway
  }

  # VLAN100 (gateway VIP holder + internal plane)
  network {
    name   = "eth1"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:49:A2"
    ip     = "10.10.100.11/24"
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)
  tags            = "golden-${local.golden};plane-${local.tag_plane};env-${local.tag_env};role-edge"

  lifecycle {
    ignore_changes = [
      network,
      features,
    ]
  }
}

resource "proxmox_lxc" "dns_edge_2" {
  depends_on = [null_resource.sdn_dns_plane]

  vmid        = 3102
  hostname    = "dns-edge-2"
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

  network {
    name   = "eth0"
    bridge = local.lan_bridge
    hwaddr = "BC:24:11:AD:49:B1"
    ip     = "192.168.11.112/24"
    gw     = local.lan_gateway
  }

  network {
    name   = "eth1"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:49:B2"
    ip     = "10.10.100.12/24"
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)
  tags            = "golden-${local.golden};plane-${local.tag_plane};env-${local.tag_env};role-edge"

  lifecycle {
    ignore_changes = [
      network,
      features,
    ]
  }
}

resource "proxmox_lxc" "dns_auth_1" {
  depends_on = [null_resource.sdn_dns_plane]

  vmid        = 3111
  hostname    = "dns-auth-1"
  target_node = "proxmox3"

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

  network {
    name   = "eth0"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:49:C1"
    ip     = "10.10.100.21/24"
    gw     = local.vlan_gw_vip
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)
  tags            = "golden-${local.golden};plane-${local.tag_plane};env-${local.tag_env};role-auth"

  lifecycle {
    ignore_changes = [
      network,
      features,
    ]
  }
}

resource "proxmox_lxc" "dns_auth_2" {
  depends_on = [null_resource.sdn_dns_plane]

  vmid        = 3112
  hostname    = "dns-auth-2"
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

  network {
    name   = "eth0"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:49:D1"
    ip     = "10.10.100.22/24"
    gw     = local.vlan_gw_vip
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)
  tags            = "golden-${local.golden};plane-${local.tag_plane};env-${local.tag_env};role-auth"

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
    dns_edge_1 = {
      hostname = proxmox_lxc.dns_edge_1.hostname
      node     = proxmox_lxc.dns_edge_1.target_node
      vmid     = proxmox_lxc.dns_edge_1.vmid
    }
    dns_edge_2 = {
      hostname = proxmox_lxc.dns_edge_2.hostname
      node     = proxmox_lxc.dns_edge_2.target_node
      vmid     = proxmox_lxc.dns_edge_2.vmid
    }
    dns_auth_1 = {
      hostname = proxmox_lxc.dns_auth_1.hostname
      node     = proxmox_lxc.dns_auth_1.target_node
      vmid     = proxmox_lxc.dns_auth_1.vmid
    }
    dns_auth_2 = {
      hostname = proxmox_lxc.dns_auth_2.hostname
      node     = proxmox_lxc.dns_auth_2.target_node
      vmid     = proxmox_lxc.dns_auth_2.vmid
    }
  }
}

output "dns_endpoints" {
  description = "DNS plane endpoints and VIPs"
  value = {
    zone        = "infra.samakia.net"
    dns_vip     = local.lan_dns_vip
    vlan_gw_vip = local.vlan_gw_vip
    dns_edge_1 = {
      lan_ip  = "192.168.11.111"
      vlan_ip = "10.10.100.11"
    }
    dns_edge_2 = {
      lan_ip  = "192.168.11.112"
      vlan_ip = "10.10.100.12"
    }
    dns_auth_1 = "10.10.100.21"
    dns_auth_2 = "10.10.100.22"
  }
}
