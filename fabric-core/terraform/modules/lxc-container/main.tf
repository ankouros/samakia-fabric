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
  tags = join(",", var.tags)

  ###########################################################################
  # Proxmox 9 guards – prevent false drift & broken updates
  ###########################################################################
  lifecycle {
    ignore_changes = [
      # Proxmox 9 API may reorder or normalize these
      network,

      # Tags handling is inconsistent across PVE 9 API calls
      tags,

      # LXC feature flags are immutable controls; delegated users must not manage them
      features,
    ]
  }
}
