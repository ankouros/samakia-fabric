#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Samakia Fabric – LXC Template Import Script (Proxmox 9 – FINAL)
###############################################################################

STORAGE="pve-nfs"
BRIDGE="vmbr0"

# TEMPLATE_ID="9000"
# TEMPLATE_NAME="fabric-lxc-ubuntu-24.04-v1"
# ROOTFS_ARCHIVE="ubuntu-24.04-lxc-rootfs.tar.gz"

TEMPLATE_ID="9001"
TEMPLATE_NAME="fabric-lxc-ubuntu-24.04-v2"
ROOTFS_ARCHIVE="ubuntu-24.04-lxc-rootfs-v2.tar.gz"


MEMORY="256"
SWAP="256"
CORES="1"
ROOTFS_SIZE="8"   # GB, template default

PCT="$(command -v pct || true)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ Must run as root on Proxmox node"
  exit 1
fi

if [[ -z "${PCT}" ]]; then
  echo "❌ pct not found – not a Proxmox VE node"
  exit 1
fi

if [[ ! -f "${ROOTFS_ARCHIVE}" ]]; then
  echo "❌ Rootfs archive not found: ${ROOTFS_ARCHIVE}"
  exit 1
fi

STORAGE_PATH="/mnt/pve/${STORAGE}/template/cache"
TARGET_TEMPLATE="${STORAGE_PATH}/${ROOTFS_ARCHIVE}"

echo "📦 Installing template into ${STORAGE_PATH}"
mkdir -p "${STORAGE_PATH}"
cp "${ROOTFS_ARCHIVE}" "${TARGET_TEMPLATE}"

# Idempotency
if "${PCT}" status "${TEMPLATE_ID}" &>/dev/null; then
  echo "⚠️ Existing CT ${TEMPLATE_ID} found – removing"
  "${PCT}" stop "${TEMPLATE_ID}" --force || true
  "${PCT}" destroy "${TEMPLATE_ID}"
fi

echo "🚀 Creating LXC container ${TEMPLATE_ID}"

"${PCT}" create "${TEMPLATE_ID}" \
  "${STORAGE}:vztmpl/${ROOTFS_ARCHIVE}" \
  --rootfs "${STORAGE}:${ROOTFS_SIZE}" \
  --hostname "${TEMPLATE_NAME}" \
  --memory "${MEMORY}" \
  --swap "${SWAP}" \
  --cores "${CORES}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp" \
  --unprivileged 1 \
  --features nesting=0,keyctl=0 \
  --ostype ubuntu \
  --onboot 0 \
  --start 0

echo "📦 Converting container to template"
"${PCT}" template "${TEMPLATE_ID}"

echo "✅ LXC template created successfully!"
echo "➡️ Template Name : ${TEMPLATE_NAME}"
echo "➡️ Storage       : ${STORAGE}"
