#!/usr/bin/env bash
set -euo pipefail

sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id

if command -v cloud-init >/dev/null 2>&1; then
  sudo cloud-init clean --logs || true
fi
