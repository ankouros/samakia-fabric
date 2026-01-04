variable "lxc_template" {
  description = "Pinned LXC template path (immutable, versioned)."
  type        = string
}

variable "ssh_public_keys" {
  description = "SSH public keys injected into LXCs (bootstrap only)."
  type        = list(string)
}

variable "storage" {
  description = "Explicit Proxmox storage for rootfs."
  type        = string
}

variable "tag_env" {
  description = "Tag environment value for Proxmox UI tags."
  type        = string
}

variable "tag_plane" {
  description = "Tag plane value for Proxmox UI tags."
  type        = string
}

variable "vlan_vnet" {
  description = "Shared VLAN bridge/vnet name."
  type        = string
}

variable "vlan_gateway" {
  description = "Shared VLAN gateway VIP."
  type        = string
}

variable "vlan_prefix" {
  description = "CIDR prefix length for VLAN IPs."
  type        = number
  default     = 24
}

variable "unprivileged" {
  description = "Whether LXCs are unprivileged."
  type        = bool
  default     = true
}

variable "patroni_nodes" {
  description = "Postgres Patroni nodes to create (map keyed by node id)."
  type = map(object({
    vmid        = number
    hostname    = string
    target_node = string
    ip          = string
    mac_address = string
    cores       = number
    memory      = number
    swap        = number
    rootfs_size = string
    role        = string
  }))
}

variable "haproxy_nodes" {
  description = "HAProxy nodes to create (map keyed by node id)."
  type = map(object({
    vmid        = number
    hostname    = string
    target_node = string
    ip          = string
    mac_address = string
    cores       = number
    memory      = number
    swap        = number
    rootfs_size = string
    role        = string
  }))
}
