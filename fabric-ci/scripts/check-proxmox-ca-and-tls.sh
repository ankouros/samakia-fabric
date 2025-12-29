#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CA_FILE="${REPO_ROOT}/ops/ca/proxmox-root-ca.crt"

api_url="${TF_VAR_pm_api_url:-${PM_API_URL:-}}"
token_id="${TF_VAR_pm_api_token_id:-${PM_API_TOKEN_ID:-}}"
token_secret="${TF_VAR_pm_api_token_secret:-${PM_API_TOKEN_SECRET:-}}"
pm_user="${TF_VAR_pm_user:-}"
pm_password="${TF_VAR_pm_password:-}"

if [[ -n "${TF_VAR_pm_tls_insecure:-}" || -n "${PM_TLS_INSECURE:-}" ]]; then
  echo "ERROR: insecure TLS env vars are forbidden (pm_tls_insecure/PM_TLS_INSECURE)." >&2
  exit 1
fi

if [[ -n "${pm_user}" || -n "${pm_password}" ]]; then
  echo "ERROR: password-based Proxmox auth is forbidden. Use API tokens only (TF_VAR_pm_api_token_id/TF_VAR_pm_api_token_secret)." >&2
  exit 1
fi

if [[ -n "${api_url}" || -n "${token_id}" || -n "${token_secret}" || -n "${pm_user}" || -n "${pm_password}" ]]; then
  if [[ ! -f "${CA_FILE}" ]]; then
    echo "ERROR: Proxmox CA is required for secure TLS but is missing: ${CA_FILE}" >&2
    echo "Run: bash ops/scripts/install-proxmox-ca.sh" >&2
    exit 1
  fi

  if command -v openssl >/dev/null 2>&1; then
    if ! openssl x509 -in "${CA_FILE}" -noout -text 2>/dev/null | grep -q "CA:TRUE"; then
      echo "ERROR: ${CA_FILE} is not a CA certificate (expected Basic Constraints CA:TRUE)." >&2
      exit 1
    fi
  fi

  if [[ ! -f "/usr/local/share/ca-certificates/proxmox-root-ca.crt" && ! -f "/etc/ssl/certs/proxmox-root-ca.pem" ]]; then
    echo "ERROR: Proxmox CA is not installed in the host trust store." >&2
    echo "Run: bash ops/scripts/install-proxmox-ca.sh" >&2
    exit 1
  fi
fi

echo "Proxmox CA/TLS guardrails OK"
