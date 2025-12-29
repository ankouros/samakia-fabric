resource "proxmox_lxc" "this" {
  ###########################################################################
  # Identity & placement
  ###########################################################################
  vmid        = var.vmid
  hostname    = var.hostname
  target_node = var.node

  ###########################################################################
  # Template (MUST already exist)
  ###########################################################################
  ostemplate = var.template
  ostype     = "ubuntu"

  ###########################################################################
  # Runtime behavior (Proxmox 9 safe)
  ###########################################################################
  unprivileged = var.unprivileged
  onboot       = true
  start        = true

  ###########################################################################
  # Compute
  ###########################################################################
  cores  = var.cores
  memory = var.memory
  swap   = var.swap

  ###########################################################################
  # Storage (EXPLICIT – avoid implicit 'local')
  ###########################################################################
  rootfs {
    storage = var.storage
    size    = "${var.rootfs_size}G"
  }

  ###########################################################################
  # Networking (simple, deterministic)
  ###########################################################################
  network {
    name   = "eth0"
    bridge = var.bridge
    hwaddr = var.mac_address
    ip     = "dhcp"
  }

  ###########################################################################
  # Bootstrap SSH (TEMPORARY ROOT ACCESS)
  #
  # - Proxmox injects keys into /root/.ssh/authorized_keys
  # - Used ONLY for first Ansible bootstrap
  # - Root SSH will be disabled by Ansible
  ###########################################################################
  ssh_public_keys = join("\n", var.ssh_public_keys)

  ###########################################################################
  # Metadata
  ###########################################################################
  tags = join(";", concat(
    [
      "golden-${regex("-(v[0-9]+)\\.tar\\.gz$", var.template)[0]}",
      "plane-${var.tag_plane}",
      "env-${var.tag_env}",
      "role-${var.tag_role}",
    ],
    var.tags_extra
  ))

  ###########################################################################
  # Proxmox 9 guards – prevent false drift & broken updates
  ###########################################################################
  lifecycle {
    precondition {
      condition     = can(regex("-(v[0-9]+)\\.tar\\.gz$", var.template))
      error_message = "Template must be versioned and immutable (expected '*-v<monotonic>.tar.gz'): ${var.template}"
    }

    precondition {
      condition     = can(regex("^[a-z0-9_-]+$", var.tag_plane)) && can(regex("^[a-z0-9_-]+$", var.tag_env)) && can(regex("^[a-z0-9_-]+$", var.tag_role))
      error_message = "Tags must be compact and UI-safe: tag_plane/tag_env/tag_role must match ^[a-z0-9_-]+$."
    }

    precondition {
      condition     = alltrue([for t in var.tags_extra : can(regex("^[A-Za-z0-9][A-Za-z0-9-._]*$", t))])
      error_message = "tags_extra entries must be Proxmox tag-safe: start with alnum and contain only [A-Za-z0-9-._] (no '=', no ';', no spaces)."
    }

    ignore_changes = [
      # Proxmox 9 API may reorder or normalize these
      network,

      # LXC feature flags are immutable controls; delegated users must not manage them
      features,
    ]
  }
}
