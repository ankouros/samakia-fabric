check "proxmox_auth" {
  assert {
    condition = (
      var.pm_api_token_id != null && var.pm_api_token_secret != null &&
      trimspace(var.pm_api_token_id) != "" && trimspace(var.pm_api_token_secret) != ""
    )
    error_message = "Set Proxmox credentials using API token auth only: (pm_api_token_id, pm_api_token_secret)."
  }

  assert {
    condition     = startswith(var.pm_api_url, "https://")
    error_message = "Proxmox API URL must be https:// (strict TLS required)."
  }

  assert {
    condition     = strcontains(var.pm_api_url, "/api2/json")
    error_message = "Proxmox API URL must include /api2/json (expected form: https://<host>:8006/api2/json)."
  }

  assert {
    condition     = strcontains(var.pm_api_token_id, "!")
    error_message = "Proxmox API token id must include '!': e.g. terraform-prov@pve!fabric-token."
  }
}

check "bootstrap_keys" {
  assert {
    condition     = length(var.ssh_public_keys) > 0
    error_message = "ssh_public_keys must contain at least one SSH public key for root key-only bootstrap."
  }

  assert {
    condition     = alltrue([for k in var.ssh_public_keys : can(regex("^ssh-", trimspace(k)))])
    error_message = "ssh_public_keys must contain valid SSH public keys (expected entries starting with 'ssh-')."
  }
}
