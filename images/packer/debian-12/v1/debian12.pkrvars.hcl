iso_url      = "file:///path/to/debian-12.iso"
iso_checksum = "sha256:<REPLACE_WITH_SHA256>"

vm_name   = "samakia-debian-12-v1"
output_dir = "artifacts/images/vm/debian-12/v1"

ssh_username = "packer"
ssh_password = "<REPLACE_WITH_PASSWORD>"

boot_command = [
  "<esc><wait>",
  "auto<wait>"
]

ansible_playbook_path = "images/ansible/playbooks/golden-base.yml"

image_id      = "debian-12"
image_version = "v1"
