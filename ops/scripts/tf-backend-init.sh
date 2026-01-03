#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage:
  tf-backend-init.sh <env> [--migrate]

Initializes Terraform with a remote S3 backend (MinIO-compatible) using strict TLS.

Required env (no values printed):
  TF_BACKEND_S3_ENDPOINT     https://minio.example.internal
  TF_BACKEND_S3_BUCKET       samakia-terraform
  TF_BACKEND_S3_REGION       us-east-1
  TF_BACKEND_S3_KEY_PREFIX   (optional; default: samakia-fabric)

  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN          (optional)

Notes:
  - State locking uses S3 lockfiles (no DynamoDB): use_lockfile = true
  - Never stores secrets in Git; backend config is generated in a temp file.
EOF
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: missing required env var: ${name}" >&2
    exit 1
  fi
}

ENV_NAME="${1:-}"
shift $(( $# >= 1 ? 1 : $# ))

if [[ -z "${ENV_NAME}" ]]; then
  usage
  exit 2
fi

migrate=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --migrate)
      migrate=1
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

TF_ENV_DIR="${REPO_ROOT}/fabric-core/terraform/envs/${ENV_NAME}"
if [[ ! -d "${TF_ENV_DIR}" ]]; then
  echo "ERROR: Terraform env directory not found: ${TF_ENV_DIR}" >&2
  exit 1
fi

if ! grep -R -q 'backend "s3"' "${TF_ENV_DIR}"/*.tf 2>/dev/null; then
  echo "ERROR: S3 backend block not found in env: ${TF_ENV_DIR} (expected backend \"s3\" {})" >&2
  exit 1
fi

require_cmd terraform
require_cmd mktemp
require_cmd rm
require_cmd awk

require_env TF_BACKEND_S3_ENDPOINT
require_env TF_BACKEND_S3_BUCKET
require_env TF_BACKEND_S3_REGION
require_env AWS_ACCESS_KEY_ID
require_env AWS_SECRET_ACCESS_KEY

if [[ ! "${TF_BACKEND_S3_ENDPOINT}" =~ ^https:// ]]; then
  echo "ERROR: TF_BACKEND_S3_ENDPOINT must be https:// (strict TLS required): ${TF_BACKEND_S3_ENDPOINT}" >&2
  exit 1
fi

key_prefix="${TF_BACKEND_S3_KEY_PREFIX:-samakia-fabric}"
key="${key_prefix}/${ENV_NAME}/terraform.tfstate"

tmp_cfg="$(mktemp)"
cleanup() { rm -f "${tmp_cfg}" 2>/dev/null || true; }
trap cleanup EXIT

cat >"${tmp_cfg}" <<EOF
bucket         = "${TF_BACKEND_S3_BUCKET}"
key            = "${key}"
region         = "${TF_BACKEND_S3_REGION}"
endpoint       = "${TF_BACKEND_S3_ENDPOINT}"
force_path_style = true

# MinIO/S3 compatibility (not a TLS bypass)
skip_region_validation      = true
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_requesting_account_id  = true

# Locking without DynamoDB
use_lockfile = true
EOF

args=(init -input=false "-backend-config=${tmp_cfg}")
if [[ "${migrate}" -eq 1 ]]; then
  # Non-interactive state migration: avoid prompts (safe after acceptance/guards).
  args+=( -migrate-state -force-copy )
else
  args+=( -reconfigure )
fi

echo "Initializing Terraform backend for env=${ENV_NAME} (endpoint set; secrets redacted)..."
terraform -chdir="${TF_ENV_DIR}" "${args[@]}" >/dev/null
echo "OK: backend initialized for ${TF_ENV_DIR}"
