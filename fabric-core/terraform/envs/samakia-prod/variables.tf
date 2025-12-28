###############################################################################
# Samakia Fabric – Proxmox Provider Variables
###############################################################################

variable "pm_api_url" {
  description = "Proxmox API URL (e.g. https://proxmox1:8006/api2/json)"
  type        = string
}

variable "pm_user" {
  description = "Proxmox API user (e.g. terraform-prov@pve). Use only for password auth."
  type        = string
  default     = null
}

variable "pm_password" {
  description = "Proxmox API password. Prefer API token auth instead."
  type        = string
  default     = null
  sensitive   = true
}

variable "pm_api_token_id" {
  description = "Proxmox API token id (e.g. terraform-prov@pve!fabric-token)."
  type        = string
  default     = null
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret."
  type        = string
  default     = null
  sensitive   = true
}

variable "ssh_public_keys" {
  description = "SSH public keys injected into LXC containers (temporary bootstrap access)."
  type        = list(string)
}
