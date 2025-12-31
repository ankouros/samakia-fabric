packer {
  required_version = ">= 1.9.0"

  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.0.0"
    }
  }
}

source "qemu" "vm" {
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = var.ssh_timeout

  disk_size = var.disk_size
  memory    = var.memory
  cpus      = var.cpus
  headless  = var.headless

  boot_command = var.boot_command
  boot_wait    = var.boot_wait

  output_directory = var.output_dir
  vm_name          = var.vm_name

  format           = "qcow2"
  shutdown_command = "sudo -S shutdown -P now"
}
