#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


DEFAULT_ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"
BACKEND_CA_DST="/usr/local/share/ca-certificates/samakia-fabric-s3-backend-ca.crt"

usage() {
  cat >&2 <<'EOF'
Usage:
  runner-env-check.sh [--file <path>]

Validates runner prerequisites without printing secrets:
  - Required environment variables are present (presence-only output)
  - Proxmox CA trust guardrails (strict TLS; no insecure flags)
  - S3 backend CA trust (when backend is configured and CA is required)

This script performs no network calls.
EOF
}

env_file="${DEFAULT_ENV_FILE}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      env_file="${2:-}"
      shift 2
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

if [[ -f "${env_file}" ]]; then
  # shellcheck disable=SC1090
  source "${env_file}"
fi

missing=0

require_present() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: missing required env var: ${name}" >&2
    missing=1
  fi
}

require_https() {
  local name="$1"
  local v="${!name:-}"
  if [[ -n "${v}" && ! "${v}" =~ ^https:// ]]; then
    echo "ERROR: ${name} must be https:// (strict TLS required): ${v}" >&2
    missing=1
  fi
}

echo "== Runner env (presence only; secrets not printed) =="
for v in \
  TF_VAR_pm_api_url TF_VAR_pm_api_token_id TF_VAR_pm_api_token_secret \
  TF_VAR_ssh_public_keys \
  TF_BACKEND_S3_ENDPOINT TF_BACKEND_S3_BUCKET TF_BACKEND_S3_REGION TF_BACKEND_S3_KEY_PREFIX \
  TF_BACKEND_S3_CA_REQUIRED TF_BACKEND_S3_CA_SRC \
  AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
  if [[ -n "${!v:-}" ]]; then
    if [[ "${v}" == *SECRET* || "${v}" == *password* || "${v}" == *pm_api_token_secret* ]]; then
      echo "${v}=set"
    else
      echo "${v}=set"
    fi
  else
    echo "${v}=missing"
  fi
done

require_present TF_VAR_pm_api_url
require_present TF_VAR_pm_api_token_id
require_present TF_VAR_pm_api_token_secret
require_present TF_VAR_ssh_public_keys

require_https TF_VAR_pm_api_url

if [[ -n "${TF_VAR_pm_api_token_id:-}" && "${TF_VAR_pm_api_token_id}" != *"!"* ]]; then
  echo "ERROR: TF_VAR_pm_api_token_id must include '!': ${TF_VAR_pm_api_token_id}" >&2
  missing=1
fi

echo
echo "== Proxmox TLS guardrails =="
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/check-proxmox-ca-and-tls.sh"

echo
echo "== SSH bootstrap key contract =="
if ! python3 - <<'PY'; then
import json
import os
import sys

raw = os.environ.get("TF_VAR_ssh_public_keys", "").strip()
try:
    data = json.loads(raw)
except Exception:
    print("ERROR: TF_VAR_ssh_public_keys must be valid JSON (expected list of SSH public keys).", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, list) or len(data) == 0 or not all(isinstance(x, str) and x.strip() for x in data):
    print("ERROR: TF_VAR_ssh_public_keys must be a non-empty JSON list of SSH public keys.", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PY
  missing=1
else
  echo "OK: TF_VAR_ssh_public_keys is a non-empty JSON list"
fi

backend_configured=0
if [[ -n "${TF_BACKEND_S3_ENDPOINT:-}" || -n "${TF_BACKEND_S3_BUCKET:-}" ]]; then
  backend_configured=1
fi

if [[ "${backend_configured}" -eq 1 ]]; then
  require_present TF_BACKEND_S3_ENDPOINT
  require_present TF_BACKEND_S3_BUCKET
  require_present TF_BACKEND_S3_REGION
  require_present AWS_ACCESS_KEY_ID
  require_present AWS_SECRET_ACCESS_KEY
  require_https TF_BACKEND_S3_ENDPOINT

  ca_required="${TF_BACKEND_S3_CA_REQUIRED:-1}"
  if [[ "${ca_required}" != "0" ]]; then
    require_present TF_BACKEND_S3_CA_SRC
    if [[ -n "${TF_BACKEND_S3_CA_SRC:-}" && ! -f "${TF_BACKEND_S3_CA_SRC}" ]]; then
      echo "ERROR: backend CA source file not found: TF_BACKEND_S3_CA_SRC=${TF_BACKEND_S3_CA_SRC}" >&2
      missing=1
    fi

    if [[ ! -f "${BACKEND_CA_DST}" && ! -f "/etc/ssl/certs/samakia-fabric-s3-backend-ca.pem" ]]; then
      echo "ERROR: backend CA is not installed in the host trust store." >&2
      echo "Run: bash \"${FABRIC_REPO_ROOT}/ops/scripts/install-s3-backend-ca.sh\"" >&2
      missing=1
    fi
  fi
fi

if [[ "${missing}" -ne 0 ]]; then
  exit 1
fi

echo
echo "OK: runner environment looks configured (presence + CA trust checks)"
