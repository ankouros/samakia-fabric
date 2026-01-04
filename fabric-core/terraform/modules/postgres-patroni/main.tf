locals {
  golden_tag = regex("-(v[0-9]+)\\.tar\\.gz$", var.lxc_template)[0]
}

resource "proxmox_lxc" "patroni" {
  for_each = var.patroni_nodes

  vmid        = each.value.vmid
  hostname    = each.value.hostname
  target_node = each.value.target_node

  ostemplate = var.lxc_template
  ostype     = "ubuntu"

  unprivileged = var.unprivileged
  onboot       = true
  start        = true

  cores  = each.value.cores
  memory = each.value.memory
  swap   = each.value.swap

  rootfs {
    storage = var.storage
    size    = each.value.rootfs_size
  }

  network {
    name   = "eth0"
    bridge = var.vlan_vnet
    hwaddr = each.value.mac_address
    ip     = "${each.value.ip}/${var.vlan_prefix}"
    gw     = var.vlan_gateway
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)

  tags = join(";", [
    "golden-${local.golden_tag}",
    "plane-${var.tag_plane}",
    "env-${var.tag_env}",
    "role-${each.value.role}",
  ])

  lifecycle {
    precondition {
      condition     = can(regex("-(v[0-9]+)\\.tar\\.gz$", var.lxc_template))
      error_message = "Template must be versioned and immutable (expected '*-v<monotonic>.tar.gz'): ${var.lxc_template}"
    }

    precondition {
      condition     = can(regex("^[a-z0-9_-]+$", var.tag_plane)) && can(regex("^[a-z0-9_-]+$", var.tag_env)) && can(regex("^[a-z0-9_-]+$", each.value.role))
      error_message = "Tags must be compact and UI-safe: tag_plane/tag_env/role must match ^[a-z0-9_-]+$."
    }

    ignore_changes = [
      network,
      features,
    ]
  }
}

resource "proxmox_lxc" "haproxy" {
  for_each = var.haproxy_nodes

  vmid        = each.value.vmid
  hostname    = each.value.hostname
  target_node = each.value.target_node

  ostemplate = var.lxc_template
  ostype     = "ubuntu"

  unprivileged = var.unprivileged
  onboot       = true
  start        = true

  cores  = each.value.cores
  memory = each.value.memory
  swap   = each.value.swap

  rootfs {
    storage = var.storage
    size    = each.value.rootfs_size
  }

  network {
    name   = "eth0"
    bridge = var.vlan_vnet
    hwaddr = each.value.mac_address
    ip     = "${each.value.ip}/${var.vlan_prefix}"
    gw     = var.vlan_gateway
  }

  ssh_public_keys = join("\n", var.ssh_public_keys)

  tags = join(";", [
    "golden-${local.golden_tag}",
    "plane-${var.tag_plane}",
    "env-${var.tag_env}",
    "role-${each.value.role}",
  ])

  lifecycle {
    precondition {
      condition     = can(regex("-(v[0-9]+)\\.tar\\.gz$", var.lxc_template))
      error_message = "Template must be versioned and immutable (expected '*-v<monotonic>.tar.gz'): ${var.lxc_template}"
    }

    precondition {
      condition     = can(regex("^[a-z0-9_-]+$", var.tag_plane)) && can(regex("^[a-z0-9_-]+$", var.tag_env)) && can(regex("^[a-z0-9_-]+$", each.value.role))
      error_message = "Tags must be compact and UI-safe: tag_plane/tag_env/role must match ^[a-z0-9_-]+$."
    }

    ignore_changes = [
      network,
      features,
    ]
  }
}
