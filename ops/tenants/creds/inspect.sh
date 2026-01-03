#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  inspect.sh --tenant <id>

Optional:
  TENANT_CREDS_FILE
  TENANT_CREDS_PASSPHRASE
  TENANT_CREDS_PASSPHRASE_FILE
EOT
}

tenant=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)
      tenant="${2:-}"
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

if [[ -z "${tenant}" ]]; then
  echo "ERROR: --tenant is required" >&2
  usage
  exit 2
fi

secrets_file_default="${HOME}/.config/samakia-fabric/tenants/${tenant}/creds.enc"
secrets_file="${TENANT_CREDS_FILE:-${secrets_file_default}}"

pass_arg=()
if [[ -n "${TENANT_CREDS_PASSPHRASE_FILE:-}" ]]; then
  if [[ ! -f "${TENANT_CREDS_PASSPHRASE_FILE}" ]]; then
    echo "ERROR: TENANT_CREDS_PASSPHRASE_FILE not found: ${TENANT_CREDS_PASSPHRASE_FILE}" >&2
    exit 2
  fi
  pass_arg=( -pass "file:${TENANT_CREDS_PASSPHRASE_FILE}" )
elif [[ -n "${TENANT_CREDS_PASSPHRASE:-}" ]]; then
  pass_arg=( -pass env:TENANT_CREDS_PASSPHRASE )
fi

if [[ ${#pass_arg[@]} -eq 0 ]]; then
  echo "ERROR: passphrase not set (TENANT_CREDS_PASSPHRASE or TENANT_CREDS_PASSPHRASE_FILE)" >&2
  exit 2
fi

if [[ ! -f "${secrets_file}" ]]; then
  echo "ERROR: secrets file not found: ${secrets_file}" >&2
  exit 2
fi

openssl enc -d -aes-256-cbc -pbkdf2 -in "${secrets_file}" "${pass_arg[@]}" | python3 -c 'import json,sys; raw=sys.stdin.read();\n\nif not raw.strip():\n    print("ERROR: decrypted secrets file is empty", file=sys.stderr); sys.exit(2)\n\ntry:\n    data=json.loads(raw)\nexcept json.JSONDecodeError as exc:\n    print(f"ERROR: secrets file is not valid JSON: {exc}", file=sys.stderr); sys.exit(2)\n\nfor key in sorted(data.keys()):\n    entry=data.get(key, {}); issued_at=entry.get("issued_at", "unknown"); print(f"{key}\\tissued_at={issued_at}")'
