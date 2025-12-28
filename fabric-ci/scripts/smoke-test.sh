#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_DIR="$ROOT_DIR/fabric-core/ansible"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd ansible-inventory

export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"

ansible-inventory -i "$ANSIBLE_DIR/inventory/terraform.py" --list >/dev/null

echo "Smoke tests completed"
