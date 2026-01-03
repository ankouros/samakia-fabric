#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"

DEFAULT_ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  runner-env-install.sh [--file <path>] [--non-interactive]

Creates a canonical runner environment file:
  ~/.config/samakia-fabric/env.sh (chmod 600)

This file is NOT committed to Git.
It contains exports needed for:
  - Terraform (Proxmox + S3 backend for MinIO)
  - Packer template upload (PM_* vars)
  - SSH bootstrap keys (TF_VAR_ssh_public_keys JSON list)

Security rules:
  - Never prints token secrets.
  - Writes secrets only to the env file (chmod 600).

Non-interactive mode:
  Requires inputs to already be present in the current environment.

Runner mode:
  RUNNER_MODE=ci forbids prompts; use --non-interactive.
  RUNNER_MODE=operator is required for prompts.
EOF
}

single_quote() {
  local s="$1"
  s="${s//\'/\'\\\'\'}"
  printf "'%s'" "${s}"
}

read_secret() {
  local prompt="$1"
  local out_var="$2"
  local value=""
  require_operator_mode
  read -r -s -p "${prompt}" value
  echo >&2
  printf -v "${out_var}" '%s' "${value}"
}

read_default() {
  local prompt="$1"
  local default="$2"
  local out_var="$3"
  local value=""
  require_operator_mode
  read -r -p "${prompt} [${default}]: " value
  if [[ -z "${value}" ]]; then
    value="${default}"
  fi
  printf -v "${out_var}" '%s' "${value}"
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: missing required env var for --non-interactive: ${name}" >&2
    exit 1
  fi
}

env_file="${DEFAULT_ENV_FILE}"
non_interactive=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      env_file="${2:-}"
      shift 2
      ;;
    --non-interactive)
      non_interactive=1
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

if [[ "${non_interactive}" -eq 1 ]]; then
  require_ci_mode
else
  require_operator_mode
fi

mkdir -p "$(dirname "${env_file}")"
chmod 700 "$(dirname "${env_file}")" || true

pm_api_url="${TF_VAR_pm_api_url:-}"
pm_api_token_id="${TF_VAR_pm_api_token_id:-}"
pm_api_token_secret="${TF_VAR_pm_api_token_secret:-}"

s3_endpoint="${TF_BACKEND_S3_ENDPOINT:-}"
s3_bucket="${TF_BACKEND_S3_BUCKET:-}"
s3_region="${TF_BACKEND_S3_REGION:-us-east-1}"
s3_key_prefix="${TF_BACKEND_S3_KEY_PREFIX:-samakia-fabric}"
s3_ca_src="${TF_BACKEND_S3_CA_SRC:-}"
s3_ca_required="${TF_BACKEND_S3_CA_REQUIRED:-1}"

aws_access_key_id="${AWS_ACCESS_KEY_ID:-}"
aws_secret_access_key="${AWS_SECRET_ACCESS_KEY:-}"

ssh_keys_json="${TF_VAR_ssh_public_keys:-}"

if [[ "${non_interactive}" -eq 1 ]]; then
  require_env TF_VAR_pm_api_url
  require_env TF_VAR_pm_api_token_id
  require_env TF_VAR_pm_api_token_secret
  require_env TF_BACKEND_S3_ENDPOINT
  require_env TF_BACKEND_S3_BUCKET
  require_env TF_BACKEND_S3_REGION
  require_env AWS_ACCESS_KEY_ID
  require_env AWS_SECRET_ACCESS_KEY

  pm_api_url="${TF_VAR_pm_api_url}"
  pm_api_token_id="${TF_VAR_pm_api_token_id}"
  pm_api_token_secret="${TF_VAR_pm_api_token_secret}"

  s3_endpoint="${TF_BACKEND_S3_ENDPOINT}"
  s3_bucket="${TF_BACKEND_S3_BUCKET}"
  s3_region="${TF_BACKEND_S3_REGION}"
  s3_key_prefix="${TF_BACKEND_S3_KEY_PREFIX:-samakia-fabric}"
  s3_ca_src="${TF_BACKEND_S3_CA_SRC:-}"
  s3_ca_required="${TF_BACKEND_S3_CA_REQUIRED:-1}"

  aws_access_key_id="${AWS_ACCESS_KEY_ID}"
  aws_secret_access_key="${AWS_SECRET_ACCESS_KEY}"
else
  read_default "Proxmox API URL (TF_VAR_pm_api_url)" "${pm_api_url:-https://proxmox1:8006/api2/json}" pm_api_url
  read_default "Proxmox API token id (TF_VAR_pm_api_token_id)" "${pm_api_token_id:-terraform-prov@pve!fabric-token}" pm_api_token_id
  read_secret "Proxmox API token secret (TF_VAR_pm_api_token_secret): " pm_api_token_secret

  read_default "MinIO/S3 endpoint (TF_BACKEND_S3_ENDPOINT)" "${s3_endpoint:-https://minio.example.internal}" s3_endpoint
  read_default "MinIO/S3 bucket (TF_BACKEND_S3_BUCKET)" "${s3_bucket:-samakia-terraform}" s3_bucket
  read_default "MinIO/S3 region (TF_BACKEND_S3_REGION)" "${s3_region:-us-east-1}" s3_region
  read_default "State key prefix (TF_BACKEND_S3_KEY_PREFIX)" "${s3_key_prefix:-samakia-fabric}" s3_key_prefix
  read_default "Require backend CA source? (TF_BACKEND_S3_CA_REQUIRED: 1/0)" "${s3_ca_required:-1}" s3_ca_required
  read_default "Backend CA source path (TF_BACKEND_S3_CA_SRC; empty if not used)" "${s3_ca_src:-}" s3_ca_src

  read_default "MinIO access key (AWS_ACCESS_KEY_ID)" "${aws_access_key_id:-}" aws_access_key_id
  read_secret "MinIO secret key (AWS_SECRET_ACCESS_KEY): " aws_secret_access_key
fi

ssh_keys_json="$(
  python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

provided = os.environ.get("TF_VAR_ssh_public_keys", "").strip()
if provided:
    try:
        data = json.loads(provided)
        if isinstance(data, list) and all(isinstance(x, str) and x.strip() for x in data):
            print(json.dumps([x.strip() for x in data]))
            sys.exit(0)
    except Exception:
        pass

keys: list[str] = []
for rel in [".ssh/id_ed25519.pub", ".ssh/id_rsa.pub"]:
    p = Path(os.environ["HOME"]) / rel
    if p.exists():
        text = p.read_text(encoding="utf-8").strip()
        if text:
            keys.append(text)

print(json.dumps(keys))
PY
)"

if python3 -c 'import json,sys; d=json.loads(sys.argv[1]); ok=isinstance(d,list) and len(d)>0 and all(isinstance(x,str) and x.strip() for x in d); sys.exit(0 if ok else 1)' "${ssh_keys_json}"; then
  :
else
  if [[ "${non_interactive}" -eq 1 ]]; then
    echo "ERROR: no SSH public keys found or provided." >&2
    echo "Fix: ensure ~/.ssh/id_ed25519.pub exists, or export TF_VAR_ssh_public_keys as a JSON list before running --non-interactive." >&2
    exit 1
  fi

  echo "ERROR: no SSH public keys found under ~/.ssh (id_ed25519.pub / id_rsa.pub)." >&2
  echo "Fix: generate a key (ssh-keygen) or export TF_VAR_ssh_public_keys as a JSON list, then rerun." >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "${tmp}" 2>/dev/null || true' EXIT

cat >"${tmp}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Samakia Fabric runner environment (local; do not commit)

export TF_VAR_pm_api_url=$(single_quote "${pm_api_url}")
export TF_VAR_pm_api_token_id=$(single_quote "${pm_api_token_id}")
export TF_VAR_pm_api_token_secret=$(single_quote "${pm_api_token_secret}")

# Also export PM_* for Proxmox API scripts (upload, inventory tooling).
export PM_API_URL=\${TF_VAR_pm_api_url}
export PM_API_TOKEN_ID=\${TF_VAR_pm_api_token_id}
export PM_API_TOKEN_SECRET=\${TF_VAR_pm_api_token_secret}

# SSH bootstrap keys injected by Terraform into /root/.ssh/authorized_keys
export TF_VAR_ssh_public_keys=$(single_quote "${ssh_keys_json}")

# Terraform S3 backend (MinIO-compatible)
export TF_BACKEND_S3_ENDPOINT=$(single_quote "${s3_endpoint}")
export TF_BACKEND_S3_BUCKET=$(single_quote "${s3_bucket}")
export TF_BACKEND_S3_REGION=$(single_quote "${s3_region}")
export TF_BACKEND_S3_KEY_PREFIX=$(single_quote "${s3_key_prefix}")
export TF_BACKEND_S3_CA_REQUIRED=$(single_quote "${s3_ca_required}")
export TF_BACKEND_S3_CA_SRC=$(single_quote "${s3_ca_src}")

# MinIO credentials (used by terraform backend via standard AWS env vars)
export AWS_ACCESS_KEY_ID=$(single_quote "${aws_access_key_id}")
export AWS_SECRET_ACCESS_KEY=$(single_quote "${aws_secret_access_key}")
EOF

install -m 0600 "${tmp}" "${env_file}"

echo "OK: wrote runner env file: ${env_file}"
echo "Next:"
echo "  source ${env_file}"
echo "  bash ops/scripts/runner-env-check.sh --file ${env_file}"
