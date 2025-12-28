###############################################################################
# Samakia Fabric – Development environment (promotion fast-lane)
###############################################################################

locals {
  # Promotion contract:
  # - this value is pinned in Git (no "latest")
  # - dev may advance faster than prod; promotion is an explicit Git change in prod
  lxc_rootfs_version = "v3"
  lxc_template       = "pve-nfs:vztmpl/ubuntu-24.04-lxc-rootfs-${local.lxc_rootfs_version}.tar.gz"
}

check "template_version_pinned" {
  assert {
    condition     = can(regex("^v[0-9]+$", local.lxc_rootfs_version))
    error_message = "Dev template version must be pinned to a monotonic value like 'v6' (no 'latest', no implicit upgrades)."
  }

  assert {
    condition     = can(regex("-v[0-9]+\\.tar\\.gz$", local.lxc_template))
    error_message = "Dev template filename must be versioned and immutable (expected '*-v<monotonic>.tar.gz')."
  }
}
