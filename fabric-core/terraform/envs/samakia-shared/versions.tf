terraform {
  required_version = ">= 1.10.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "= 3.0.2-rc07"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
