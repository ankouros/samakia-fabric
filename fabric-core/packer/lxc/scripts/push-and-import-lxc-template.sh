#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Samakia Fabric – Remote LXC Template Push & Import (FIXED)
###############################################################################

# -----------------------------
# Remote Proxmox target
# -----------------------------
PROXMOX_HOST="192.168.11.90"
PROXMOX_USER="root"
REMOTE_DIR="/root"

# -----------------------------
# Local paths
# -----------------------------
#ROOTFS_ARCHIVE="ubuntu-24.04-lxc-rootfs.tar.gz"
ROOTFS_ARCHIVE="${ROOTFS_ARCHIVE:-ubuntu-24.04-lxc-rootfs-v4.tar.gz}"

IMPORT_SCRIPT="../scripts/import-lxc-template.sh"

# -----------------------------
# Preconditions
# -----------------------------
[[ -f "${ROOTFS_ARCHIVE}" ]] || { echo "❌ Missing ${ROOTFS_ARCHIVE}"; exit 1; }
[[ -f "${IMPORT_SCRIPT}" ]] || { echo "❌ Missing ${IMPORT_SCRIPT}"; exit 1; }

command -v ssh >/dev/null || { echo "❌ ssh not installed"; exit 1; }
command -v scp >/dev/null || { echo "❌ scp not installed"; exit 1; }

echo "🚀 Pushing LXC template to ${PROXMOX_USER}@${PROXMOX_HOST}"

# -----------------------------
# Copy artifacts
# -----------------------------
scp "${ROOTFS_ARCHIVE}" \
  "${PROXMOX_USER}@${PROXMOX_HOST}:${REMOTE_DIR}/"

scp "${IMPORT_SCRIPT}" \
  "${PROXMOX_USER}@${PROXMOX_HOST}:${REMOTE_DIR}/import-lxc-template.sh"

# -----------------------------
# Remote execution (CORRECT WAY)
# -----------------------------
echo "🖥️ Executing import on Proxmox node..."

ssh -tt "${PROXMOX_USER}@${PROXMOX_HOST}" \
  "chmod +x /root/import-lxc-template.sh && bash -lc '/root/import-lxc-template.sh'"


echo "✅ Remote LXC template import completed successfully!"
