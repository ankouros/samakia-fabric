#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Samakia Fabric – Upload LXC template via Proxmox API token
#
# Uploads a Proxmox-compatible LXC rootfs tar.gz into the specified storage as
# `vztmpl` content, without requiring SSH/root access on the Proxmox node.
#
# Required env:
# - PM_API_URL            e.g. https://proxmox1:8006/api2/json
# - PM_API_TOKEN_ID       e.g. terraform-prov@pve!fabric-token
# - PM_API_TOKEN_SECRET   token secret (DO NOT COMMIT)
#
# Optional env:
# - PM_NODE               default: proxmox1
# - PM_STORAGE            default: pve-nfs
#
# Usage:
#   PM_API_URL=... PM_API_TOKEN_ID=... PM_API_TOKEN_SECRET=... \
#     ./upload-lxc-template-via-api.sh /path/to/ubuntu-24.04-lxc-rootfs-v3.tar.gz
###############################################################################

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: missing required env var: ${name}" >&2
    exit 1
  fi
}

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: missing required command: ${name}" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd python3

require_env PM_API_URL
require_env PM_API_TOKEN_ID
require_env PM_API_TOKEN_SECRET

PM_NODE="${PM_NODE:-proxmox1}"
PM_STORAGE="${PM_STORAGE:-pve-nfs}"

ROOTFS_ARCHIVE="${1:-}"
if [[ -z "${ROOTFS_ARCHIVE}" ]]; then
  echo "Usage: $0 /path/to/<rootfs>.tar.gz" >&2
  exit 2
fi

if [[ ! -f "${ROOTFS_ARCHIVE}" ]]; then
  echo "ERROR: rootfs archive not found: ${ROOTFS_ARCHIVE}" >&2
  exit 1
fi

ARCHIVE_BASENAME="$(basename "${ROOTFS_ARCHIVE}")"
if [[ ! "${ARCHIVE_BASENAME}" =~ -v([0-9]+)\.tar\.gz$ ]]; then
  echo "ERROR: rootfs archive must be versioned and immutable: expected '*-v<monotonic>.tar.gz' but got '${ARCHIVE_BASENAME}'" >&2
  exit 1
fi

AUTH_HEADER="Authorization: PVEAPIToken=${PM_API_TOKEN_ID}=${PM_API_TOKEN_SECRET}"
UPLOAD_URL="${PM_API_URL%/}/nodes/${PM_NODE}/storage/${PM_STORAGE}/upload"
CONTENT_URL="${PM_API_URL%/}/nodes/${PM_NODE}/storage/${PM_STORAGE}/content"

EXPECTED_VOLID="${PM_STORAGE}:vztmpl/${ARCHIVE_BASENAME}"

echo "Checking if template already exists (immutable rule): ${EXPECTED_VOLID}"

# NOTE: Use a proper multi-line python program. Compound statements (for/if)
# cannot follow ";" on the same logical line.
curl -fsS -H "${AUTH_HEADER}" "${CONTENT_URL}" \
  | python3 -c $'import json,sys\n'\
$'expected=sys.argv[1]\n'\
$'payload=json.load(sys.stdin)\n'\
$'for item in payload.get("data", []):\n'\
$'  volid=item.get("volid")\n'\
$'  if volid == expected:\n'\
$'    print(f"ERROR: template already exists (immutable): {expected}", file=sys.stderr)\n'\
$'    sys.exit(1)\n'\
$'sys.exit(0)\n' "${EXPECTED_VOLID}"

echo "Uploading ${ARCHIVE_BASENAME} to ${PM_NODE}/${PM_STORAGE} as vztmpl..."

curl -fsS \
  -H "${AUTH_HEADER}" \
  -X POST \
  -F "content=vztmpl" \
  -F "filename=@${ROOTFS_ARCHIVE}" \
  "${UPLOAD_URL}" >/dev/null

echo "Upload completed: ${EXPECTED_VOLID}"
