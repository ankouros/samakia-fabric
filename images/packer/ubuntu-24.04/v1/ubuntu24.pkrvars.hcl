iso_url      = "file:///path/to/ubuntu-24.04.iso"
iso_checksum = "sha256:<REPLACE_WITH_SHA256>"

vm_name   = "samakia-ubuntu-24.04-v1"
output_dir = "artifacts/images/vm/ubuntu-24.04/v1"

ssh_username = "packer"
ssh_password = "<REPLACE_WITH_PASSWORD>"

boot_command = [
  "<esc><wait>",
  "auto<wait>"
]

ansible_playbook_path = "images/ansible/playbooks/golden-base.yml"

image_id      = "ubuntu-24.04"
image_version = "v1"

apt_snapshot_url = "https://snapshot.ubuntu.com/ubuntu/20260102T000000Z"
apt_snapshot_security_url = "https://snapshot.ubuntu.com/ubuntu/20260102T000000Z"
