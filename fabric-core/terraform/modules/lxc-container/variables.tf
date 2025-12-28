###############################################################################
# Core identity
###############################################################################

variable "vmid" {
  description = "Unique VMID for the LXC container. Must be managed externally."
  type        = number
}

variable "hostname" {
  description = "Container hostname."
  type        = string
}

variable "node" {
  description = "Target Proxmox node (e.g. proxmox1)."
  type        = string
}

###############################################################################
# Template & storage (Proxmox 9 safe)
###############################################################################

variable "template" {
  description = <<EOT
Existing LXC template in Proxmox storage.
Must be in the form: <storage>:vztmpl/<file.tar.gz>
EOT
  type        = string

  validation {
    condition     = can(regex("^.+:vztmpl/.+\\.tar\\.gz$", var.template))
    error_message = "Template must be in the form <storage>:vztmpl/<file>.tar.gz"
  }
}


variable "storage" {
  description = "Storage for container rootfs (e.g. pve-nfs). Must NOT be 'local' if disabled."
  type        = string
}

variable "rootfs_size" {
  description = "Root filesystem size in GB."
  type        = number
  default     = 16
  validation {
    condition     = var.rootfs_size >= 8
    error_message = "rootfs_size must be at least 8GB"
  }
}

###############################################################################
# Compute resources
###############################################################################

variable "cores" {
  description = "Number of CPU cores."
  type        = number
  default     = 1
}

variable "memory" {
  description = "Memory in MB."
  type        = number
  default     = 512
}

variable "swap" {
  description = "Swap in MB."
  type        = number
  default     = 512
}

###############################################################################
# Networking
###############################################################################

variable "bridge" {
  description = "Network bridge (e.g. vmbr0)."
  type        = string
}

variable "mac_address" {
  description = "Optional MAC address for the primary NIC (eth0). Useful for stable DHCP leases."
  type        = string
  default     = null

  validation {
    condition     = var.mac_address == null || can(regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", var.mac_address))
    error_message = "mac_address must be a valid MAC address (e.g. BC:24:11:AD:49:D4) or null."
  }
}

###############################################################################
# Access & metadata
###############################################################################

variable "ssh_public_keys" {
  description = "List of SSH public keys injected via cloud-init."
  type        = list(string)
}

variable "tags" {
  description = "List of Proxmox tags. Used for grouping and automation."
  type        = list(string)
  default     = []
}

###############################################################################
# Security & behavior
###############################################################################

variable "unprivileged" {
  description = "Run container as unprivileged (strongly recommended)."
  type        = bool
  default     = true
}
