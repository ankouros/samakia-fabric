#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

missing=0

require_tool() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: required tool missing: $name" >&2
    missing=1
  else
    echo "OK: ${name} present"
  fi
}

optional_tool() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "WARN: optional tool missing: $name (offline inspection may be limited)" >&2
  else
    echo "OK: ${name} present"
  fi
}

require_tool packer
require_tool qemu-img
require_tool ansible-playbook
require_tool python3
require_tool sha256sum

optional_tool guestfish
optional_tool virt-customize
optional_tool gpg

if [[ "$missing" -ne 0 ]]; then
  echo "FAIL: missing required tools" >&2
  exit 1
fi

printf '%s\n' "PASS: required tools present"
