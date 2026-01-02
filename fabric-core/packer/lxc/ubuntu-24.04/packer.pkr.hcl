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
  default = "ubuntu@sha256:c35e29c9450151419d9448b0fd75374fec4fff364a27f176fb458d472dfc9e54"
}

variable "apt_snapshot_url" {
  type    = string
  default = "https://snapshot.ubuntu.com/ubuntu/20260102T000000Z"
}

variable "fabric_version" {
  type    = string
  default = "v3"
}

variable "image_name" {
  type    = string
  default = "ubuntu-24.04-lxc-rootfs"
}

variable "image_version" {
  type    = string
  default = "v3"
}

variable "build_time" {
  type    = string
  default = "unknown"
}

variable "git_sha" {
  type    = string
  default = "unknown"
}

variable "packer_template_id" {
  type    = string
  default = "fabric-core/packer/lxc/ubuntu-24.04/packer.pkr.hcl"
}

variable "artifact_basename" {
  type    = string
  default = "ubuntu-24.04-lxc-rootfs-v3"
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
      "DEBIAN_FRONTEND=noninteractive",
      "APT_SNAPSHOT_URL=${var.apt_snapshot_url}",
      "SAMAKIA_IMAGE_NAME=${var.image_name}",
      "SAMAKIA_IMAGE_VERSION=${var.image_version}",
      "SAMAKIA_BUILD_UTC=${var.build_time}",
      "SAMAKIA_GIT_SHA=${var.git_sha}",
      "SAMAKIA_PACKER_TEMPLATE_ID=${var.packer_template_id}"
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
