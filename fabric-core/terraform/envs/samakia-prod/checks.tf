check "proxmox_auth" {
  assert {
    condition = (
      (var.pm_api_token_id != null && var.pm_api_token_secret != null) ||
      (var.pm_user != null && var.pm_password != null)
    )
    error_message = "Set Proxmox credentials using either (pm_api_token_id, pm_api_token_secret) or (pm_user, pm_password)."
  }

  assert {
    condition = !(
      (var.pm_api_token_id != null || var.pm_api_token_secret != null) &&
      (var.pm_user != null || var.pm_password != null)
    )
    error_message = "Do not set both token auth and password auth variables at the same time."
  }
}
