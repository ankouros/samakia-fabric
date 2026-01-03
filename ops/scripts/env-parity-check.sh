#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENVS_DIR="${REPO_ROOT}/fabric-core/terraform/envs"

usage() {
  cat >&2 <<'EOF'
Usage:
  env-parity-check.sh

Enforces structural equivalence across Terraform envs (dev/staging/prod):
  - required Terraform version
  - provider constraints and pinning
  - backend presence (remote state)
  - required files and core outputs for inventory

This is a guardrail: it checks shape, not environment-specific values.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

required_envs=(samakia-dev samakia-staging samakia-prod)
missing=0

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: missing required file: ${path}" >&2
    missing=1
  fi
}

require_match() {
  local path="$1"
  local pattern="$2"
  local msg="$3"
  if [[ -f "${path}" ]]; then
    if ! rg -n "${pattern}" "${path}" >/dev/null 2>&1; then
      echo "ERROR: ${msg}: ${path}" >&2
      missing=1
    fi
  fi
}

require_fixed() {
  local path="$1"
  local literal="$2"
  local msg="$3"
  if [[ -f "${path}" ]]; then
    if ! rg -n -F -- "${literal}" "${path}" >/dev/null 2>&1; then
      echo "ERROR: ${msg}: ${path}" >&2
      missing=1
    fi
  fi
}

require_dir() {
  local path="$1"
  if [[ ! -d "${path}" ]]; then
    echo "ERROR: missing required directory: ${path}" >&2
    missing=1
  fi
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

require_cmd rg

for e in "${required_envs[@]}"; do
  require_dir "${ENVS_DIR}/${e}"
done

expected_tf_required_version=""
expected_provider_version=""

for e in "${required_envs[@]}"; do
  d="${ENVS_DIR}/${e}"

  require_file "${d}/backend.tf"
  require_file "${d}/provider.tf"
  require_file "${d}/versions.tf"
  require_file "${d}/variables.tf"
  require_file "${d}/checks.tf"
  require_file "${d}/main.tf"
  require_file "${d}/terraform.tfvars.example"

  require_fixed "${d}/backend.tf" 'backend "s3"' "missing backend \"s3\" block"
  require_fixed "${d}/provider.tf" 'provider "proxmox"' "missing proxmox provider block"
  require_fixed "${d}/checks.tf" 'check "proxmox_auth"' "missing proxmox_auth check"
  require_match "${d}/versions.tf" "telmate/proxmox" "provider source must be telmate/proxmox"
  require_fixed "${d}/main.tf" 'output "lxc_inventory"' "missing output lxc_inventory (inventory contract)"

  tf_required_version="$(awk -F'"' '/required_version/{print $2; exit}' "${d}/versions.tf" || true)"
  if [[ -z "${tf_required_version}" ]]; then
    echo "ERROR: required_version not found in ${d}/versions.tf" >&2
    missing=1
  fi
  if [[ -z "${expected_tf_required_version}" ]]; then
    expected_tf_required_version="${tf_required_version}"
  elif [[ "${tf_required_version}" != "${expected_tf_required_version}" ]]; then
    echo "ERROR: required_version mismatch in ${d}/versions.tf: expected ${expected_tf_required_version} got ${tf_required_version}" >&2
    missing=1
  fi

  # Provider version parity check (across envs): extract proxmox provider version from versions.tf
  provider_version="$(
    awk '
      BEGIN { in_req=0; in_prox=0 }
      /required_providers[[:space:]]*{/ { in_req=1 }
      in_req && /proxmox[[:space:]]*=/ { in_prox=1 }
      in_req && in_prox && /version[[:space:]]*=/ {
        n = split($0, a, "\"")
        if (n >= 3) { print a[2]; exit }
      }
      in_req && /}/ {
        if (in_prox) { in_prox=0 } else { in_req=0 }
      }
    ' "${d}/versions.tf" || true
  )"

  if [[ -z "${provider_version}" ]]; then
    echo "ERROR: proxmox provider version not found in ${d}/versions.tf" >&2
    missing=1
  elif [[ -z "${expected_provider_version}" ]]; then
    expected_provider_version="${provider_version}"
  elif [[ "${provider_version}" != "${expected_provider_version}" ]]; then
    echo "ERROR: proxmox provider version mismatch in ${d}/versions.tf: expected ${expected_provider_version} got ${provider_version}" >&2
    missing=1
  fi

  # Keep the explicit pin guard as well (must match contract)
  if ! rg -n -F -- "3.0.2-rc07" "${d}/versions.tf" >/dev/null 2>&1; then
    echo "ERROR: proxmox provider version must be pinned to 3.0.2-rc07 in ${d}/versions.tf" >&2
    missing=1
  fi

  # Variable contract (types + presence).
  require_fixed "${d}/variables.tf" 'variable "pm_api_url"' "missing variable pm_api_url"
  require_fixed "${d}/variables.tf" 'variable "pm_api_token_id"' "missing variable pm_api_token_id"
  require_fixed "${d}/variables.tf" 'variable "pm_api_token_secret"' "missing variable pm_api_token_secret"
  require_fixed "${d}/variables.tf" 'variable "ssh_public_keys"' "missing variable ssh_public_keys"
done

if [[ "${missing}" -ne 0 ]]; then
  exit 1
fi

echo "OK: env parity check passed (dev/staging/prod structural equivalence)"
