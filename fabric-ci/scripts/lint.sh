#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/fabric-core/terraform"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd terraform

"$ROOT_DIR/fabric-ci/scripts/enforce-terraform-provider.sh"

terraform -chdir="$TERRAFORM_DIR" fmt -check -recursive

echo "Lint checks completed"
