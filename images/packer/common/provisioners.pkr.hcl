build {
  name    = "samakia-vm-${var.image_id}-${var.image_version}"
  sources = ["source.qemu.vm"]

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    scripts = [
      "${path.root}/scripts/cloud-init-ensure.sh"
    ]
  }

  provisioner "ansible" {
    playbook_file = var.ansible_playbook_path
    extra_arguments = [
      "--extra-vars",
      "golden_base_image_id=${var.image_id} golden_base_image_version=${var.image_version} golden_base_build_time=${var.build_time}"
    ]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    scripts = [
      "${path.root}/scripts/pkg-manifest.sh",
      "${path.root}/scripts/ssh-hardening.sh",
      "${path.root}/scripts/firstboot-cleanup.sh"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "echo 'VM image built:'",
      "echo '  name=${var.vm_name}'",
      "echo '  output_dir=${var.output_dir}'"
    ]
  }
}
