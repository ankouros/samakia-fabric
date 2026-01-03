#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CA_SRC="${REPO_ROOT}/ops/ca/proxmox-root-ca.crt"
CA_DST="/usr/local/share/ca-certificates/proxmox-root-ca.crt"

if [[ ! -f "${CA_SRC}" ]]; then
  echo "ERROR: missing CA file: ${CA_SRC}" >&2
  exit 1
fi

if ! command -v update-ca-certificates >/dev/null 2>&1; then
  echo "ERROR: update-ca-certificates not found (expected on Debian/Ubuntu hosts)" >&2
  exit 1
fi

echo "Installing Proxmox CA into host trust store..."
sudo install -m 0644 "${CA_SRC}" "${CA_DST}"
sudo update-ca-certificates

echo "OK: installed ${CA_DST}"
