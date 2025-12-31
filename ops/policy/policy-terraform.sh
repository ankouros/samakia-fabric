#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

require_cmd terraform
require_cmd mktemp
require_cmd rm

"${FABRIC_REPO_ROOT}/fabric-ci/scripts/enforce-terraform-provider.sh"

terraform -chdir="${FABRIC_REPO_ROOT}/fabric-core/terraform" fmt -check -recursive

for env_dir in "${FABRIC_REPO_ROOT}/fabric-core/terraform/envs"/*; do
  if [[ -d "${env_dir}" ]] && compgen -G "${env_dir}/*.tf" >/dev/null; then
    tf_data_dir="$(mktemp -d)"
    TF_DATA_DIR="${tf_data_dir}" terraform -chdir="${env_dir}" init -backend=false -input=false -lockfile=readonly >/dev/null
    TF_DATA_DIR="${tf_data_dir}" terraform -chdir="${env_dir}" validate
    rm -rf "${tf_data_dir}" 2>/dev/null || true
  fi
done
