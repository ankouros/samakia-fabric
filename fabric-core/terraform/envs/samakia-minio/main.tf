###############################################################################
# Samakia Fabric – MinIO HA (Terraform state backend)
###############################################################################

locals {
  ###########################################################################
  # Promotion contract: pinned template version (no "latest")
  ###########################################################################
  lxc_rootfs_version = "v3"
  lxc_template       = "pve-nfs:vztmpl/ubuntu-24.04-lxc-rootfs-${local.lxc_rootfs_version}.tar.gz"

  ###########################################################################
  # Network contracts (explicit)
  ###########################################################################
  lan_cidr      = "192.168.11.0/24"
  lan_gateway   = "192.168.11.1"
  lan_bridge    = "vmbr0"
  minio_lan_vip = "192.168.11.101"

  vlan_id     = 140
  vlan_zone   = "zminio"
  vlan_vnet   = "vminio"
  vlan_cidr   = "10.10.140.0/24"
  vlan_gw_vip = "10.10.140.1"
}

check "template_version_pinned" {
  assert {
    condition     = can(regex("^v[0-9]+$", local.lxc_rootfs_version))
    error_message = "MinIO env template version must be pinned to a monotonic value like 'v6' (no 'latest', no implicit upgrades)."
  }

  assert {
    condition     = can(regex("-v[0-9]+\\.tar\\.gz$", local.lxc_template))
    error_message = "MinIO env template filename must be versioned and immutable (expected '*-v<monotonic>.tar.gz')."
  }
}

###############################################################################
# Proxmox SDN prerequisites (stateful VLAN plane)
#
# Telmate provider lacks SDN primitives; ensure SDN via Proxmox HTTP API
# using token auth (create-once, validate shape, fail loud on mismatch).
###############################################################################

resource "null_resource" "sdn_stateful_plane" {
  triggers = {
    zone   = local.vlan_zone
    vnet   = local.vlan_vnet
    vlan   = tostring(local.vlan_id)
    subnet = local.vlan_cidr
    gw     = local.vlan_gw_vip
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/../../../..//ops/scripts/proxmox-sdn-ensure-stateful-plane.sh"
  }
}

###############################################################################
# LXC containers
###############################################################################

resource "proxmox_lxc" "minio_edge_1" {
  depends_on = [null_resource.sdn_stateful_plane]

  vmid        = 3201
  hostname    = "minio-edge-1"
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

  # LAN (VIP holder + runner endpoint)
  network {
    name   = "eth0"
    bridge = local.lan_bridge
    hwaddr = "BC:24:11:AD:50:A1"
    ip     = "192.168.11.111/24"
    gw     = local.lan_gateway
  }

  # VLAN140 (stateful plane gateway VIP holder)
  network {
    name   = "eth1"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:50:A2"
    ip     = "10.10.140.2/24"
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)
  tags            = "fabric,minio,edge,vlan140"

  lifecycle {
    ignore_changes = [
      network,
      tags,
      features,
    ]
  }
}

resource "proxmox_lxc" "minio_edge_2" {
  depends_on = [null_resource.sdn_stateful_plane]

  vmid        = 3202
  hostname    = "minio-edge-2"
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
    hwaddr = "BC:24:11:AD:50:B1"
    ip     = "192.168.11.112/24"
    gw     = local.lan_gateway
  }

  network {
    name   = "eth1"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:50:B2"
    ip     = "10.10.140.3/24"
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)
  tags            = "fabric,minio,edge,vlan140"

  lifecycle {
    ignore_changes = [
      network,
      tags,
      features,
    ]
  }
}

resource "proxmox_lxc" "minio_1" {
  depends_on = [null_resource.sdn_stateful_plane]

  vmid        = 3211
  hostname    = "minio-1"
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
    size    = "30G"
  }

  network {
    name   = "eth0"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:50:C1"
    ip     = "10.10.140.11/24"
    gw     = local.vlan_gw_vip
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)
  tags            = "fabric,minio,node,vlan140"

  lifecycle {
    ignore_changes = [
      network,
      tags,
      features,
    ]
  }
}

resource "proxmox_lxc" "minio_2" {
  depends_on = [null_resource.sdn_stateful_plane]

  vmid        = 3212
  hostname    = "minio-2"
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
    size    = "30G"
  }

  network {
    name   = "eth0"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:50:D1"
    ip     = "10.10.140.12/24"
    gw     = local.vlan_gw_vip
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)
  tags            = "fabric,minio,node,vlan140"

  lifecycle {
    ignore_changes = [
      network,
      tags,
      features,
    ]
  }
}

resource "proxmox_lxc" "minio_3" {
  depends_on = [null_resource.sdn_stateful_plane]

  vmid        = 3213
  hostname    = "minio-3"
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
    size    = "30G"
  }

  network {
    name   = "eth0"
    bridge = local.vlan_vnet
    hwaddr = "BC:24:11:AD:50:E1"
    ip     = "10.10.140.13/24"
    gw     = local.vlan_gw_vip
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)
  tags            = "fabric,minio,node,vlan140"

  lifecycle {
    ignore_changes = [
      network,
      tags,
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
    minio_edge_1 = {
      hostname = proxmox_lxc.minio_edge_1.hostname
      node     = proxmox_lxc.minio_edge_1.target_node
      vmid     = proxmox_lxc.minio_edge_1.vmid
    }
    minio_edge_2 = {
      hostname = proxmox_lxc.minio_edge_2.hostname
      node     = proxmox_lxc.minio_edge_2.target_node
      vmid     = proxmox_lxc.minio_edge_2.vmid
    }
    minio_1 = {
      hostname = proxmox_lxc.minio_1.hostname
      node     = proxmox_lxc.minio_1.target_node
      vmid     = proxmox_lxc.minio_1.vmid
    }
    minio_2 = {
      hostname = proxmox_lxc.minio_2.hostname
      node     = proxmox_lxc.minio_2.target_node
      vmid     = proxmox_lxc.minio_2.vmid
    }
    minio_3 = {
      hostname = proxmox_lxc.minio_3.hostname
      node     = proxmox_lxc.minio_3.target_node
      vmid     = proxmox_lxc.minio_3.vmid
    }
  }
}

output "minio_endpoints" {
  description = "MinIO endpoints and VIPs"
  value = {
    s3_vip      = local.minio_lan_vip
    console_vip = local.minio_lan_vip
    vlan_gw_vip = local.vlan_gw_vip
    minio_nodes = [
      "10.10.140.11",
      "10.10.140.12",
      "10.10.140.13",
    ]
    minio_edges = {
      minio_edge_1 = { lan_ip = "192.168.11.111", vlan_ip = "10.10.140.2" }
      minio_edge_2 = { lan_ip = "192.168.11.112", vlan_ip = "10.10.140.3" }
    }
  }
}
