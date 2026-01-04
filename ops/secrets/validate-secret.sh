#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

usage() {
  cat >&2 <<'EOT'
Usage:
  validate-secret.sh <secret-path> --require <field> [--require <field> ...]

Notes:
  - Uses SECRETS_BACKEND (default: vault).
  - Never prints secret values.
  - Fails if the secret or required fields are missing or empty.
EOT
}

secret_path=""
requires=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --require needs a field name" >&2
        exit 2
      fi
      requires+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "${secret_path}" ]]; then
        secret_path="$1"
        shift 1
      else
        echo "ERROR: unexpected argument: $1" >&2
        usage
        exit 2
      fi
      ;;
  esac
done

if [[ -z "${secret_path}" ]]; then
  usage
  exit 2
fi

if [[ ${#requires[@]} -eq 0 ]]; then
  echo "ERROR: at least one --require field is required" >&2
  exit 2
fi

backend="${SECRETS_BACKEND:-vault}"
if [[ "${backend}" == "vault" ]]; then
  vault_mount="${VAULT_KV_MOUNT:-secret}"
  if [[ "${secret_path}" == "${vault_mount}/"* ]]; then
    secret_path="${secret_path#"${vault_mount}"/}"
  fi
fi

secrets_script="${FABRIC_REPO_ROOT}/ops/secrets/secrets.sh"
if [[ ! -x "${secrets_script}" ]]; then
  echo "ERROR: secrets helper not found or not executable: ${secrets_script}" >&2
  exit 2
fi

if ! SECRETS_BACKEND="${backend}" bash "${secrets_script}" get "${secret_path}" >/dev/null 2>&1; then
  echo "FAIL: secret not found or unreadable: ${secret_path} (backend: ${backend})" >&2
  exit 1
fi

for field in "${requires[@]}"; do
  value=""
  if ! value="$(SECRETS_BACKEND="${backend}" bash "${secrets_script}" get "${secret_path}" "${field}" 2>/dev/null)"; then
    echo "FAIL: secret ${secret_path} missing required field: ${field}" >&2
    exit 1
  fi

  trimmed="${value#"${value%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  if [[ -z "${trimmed}" ]]; then
    echo "FAIL: secret ${secret_path} field ${field} is empty" >&2
    exit 1
  fi
done

echo "PASS: secret ${secret_path} has required non-empty fields"
