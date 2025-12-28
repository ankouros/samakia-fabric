packer {
  required_version = ">= 1.9.0"

  required_plugins {
    docker = {
      source  = "github.com/hashicorp/docker"
      version = ">= 1.1.0"
    }
  }
}

###############################################################################
# Variables (Golden Image Contract)
###############################################################################

variable "ubuntu_version" {
  type    = string
  default = "24.04"
}

variable "ubuntu_image" {
  type    = string
  default = "ubuntu:24.04"
}

variable "fabric_version" {
  type    = string
  default = "v4"
}

variable "artifact_basename" {
  type    = string
  default = "ubuntu-24.04-lxc-rootfs-v4"
}

###############################################################################
# Docker source (builds plain rootfs tar)
###############################################################################

source "docker" "ubuntu" {
  image       = var.ubuntu_image
  export_path = "${var.artifact_basename}.tar"
}

###############################################################################
# Build
###############################################################################

build {
  name    = "samakia-fabric-lxc-ubuntu-${var.ubuntu_version}-${var.fabric_version}"
  sources = ["source.docker.ubuntu"]

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    scripts = [
      "provision.sh",
      "cleanup.sh"
    ]
  }

  ###########################################################################
  # Compress rootfs to tar.gz (Proxmox-compatible)
  ###########################################################################

  post-processor "shell-local" {
    inline = [
      "echo 'Compressing rootfs to tar.gz...'",
      "gzip -9 -n ${var.artifact_basename}.tar",
      "echo 'Artifact created: ${var.artifact_basename}.tar.gz'"
    ]
  }
}
