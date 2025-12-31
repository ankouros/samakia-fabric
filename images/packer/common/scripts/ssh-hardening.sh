#!/usr/bin/env bash
set -euo pipefail

sshd_config="/etc/ssh/sshd_config"

if [[ -f "$sshd_config" ]]; then
  sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
  sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' "$sshd_config"
  sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_config"
fi
