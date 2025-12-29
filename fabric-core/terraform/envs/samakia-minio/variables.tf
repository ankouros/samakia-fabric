###############################################################################
# Samakia Fabric – Proxmox Provider Variables (MinIO env)
###############################################################################

variable "pm_api_url" {
  description = "Proxmox API URL (e.g. https://proxmox1:8006/api2/json)"
  type        = string
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

variable "fabric_repo_root" {
  description = "Absolute path to the Samakia Fabric repo root (used for bootstrap-safe local-exec script paths)."
  type        = string
}
