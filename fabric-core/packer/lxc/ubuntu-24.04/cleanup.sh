#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# Package manager cleanup
# -----------------------------------------------------------------------------
apt-get autoremove -y --purge
apt-get autoclean -y
apt-get clean -y

# -----------------------------------------------------------------------------
# Remove package lists (image size reduction)
# -----------------------------------------------------------------------------
rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Cloud-init cleanup (force first-boot re-run)
# -----------------------------------------------------------------------------
cloud-init clean --logs || true
rm -rf /var/lib/cloud/*

# -----------------------------------------------------------------------------
# Logs cleanup (golden image should be silent)
# -----------------------------------------------------------------------------
rm -rf /var/log/*

# Recreate essential log directories
mkdir -p /var/log/journal
chmod 2755 /var/log/journal

# -----------------------------------------------------------------------------
# Temporary files cleanup
# -----------------------------------------------------------------------------
rm -rf /tmp/*
rm -rf /var/tmp/*

# -----------------------------------------------------------------------------
# SSH runtime leftovers (host keys already removed in provision.sh)
# -----------------------------------------------------------------------------
rm -rf /run/sshd
rm -rf /var/run/sshd

# -----------------------------------------------------------------------------
# Systemd runtime cleanup
# -----------------------------------------------------------------------------
rm -rf /run/*
rm -rf /var/run/*

# -----------------------------------------------------------------------------
# Bash history & caches (defensive)
# -----------------------------------------------------------------------------
rm -f /root/.bash_history
rm -rf /root/.cache

# -----------------------------------------------------------------------------
# Ensure machine-id is empty (critical for clones)
# -----------------------------------------------------------------------------
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# -----------------------------------------------------------------------------
# Final safety notes
# -----------------------------------------------------------------------------
# - No users removed (only root exists)
# - No kernel / bootloader touched
# - Safe for unprivileged LXC
# -----------------------------------------------------------------------------
