#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  revoke.sh --tenant <id> --consumer <consumer>

Guards:
  REVOKE_EXECUTE=1
EOT
}

tenant=""
consumer=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)
      tenant="${2:-}"
      shift 2
      ;;
    --consumer)
      consumer="${2:-}"
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

if [[ -z "${tenant}" || -z "${consumer}" ]]; then
  echo "ERROR: --tenant and --consumer are required" >&2
  usage
  exit 2
fi

if [[ "${REVOKE_EXECUTE:-0}" != "1" ]]; then
  echo "ERROR: REVOKE_EXECUTE=1 is required to revoke credentials" >&2
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

plaintext_tmp="$(mktemp)"
trap 'rm -f "${plaintext_tmp}"' EXIT

openssl enc -d -aes-256-cbc -pbkdf2 -in "${secrets_file}" "${pass_arg[@]}" >"${plaintext_tmp}"

python3 - <<PY
import json
from pathlib import Path

path = Path("${plaintext_tmp}")
raw = path.read_text()
try:
    data = json.loads(raw) if raw.strip() else {}
except json.JSONDecodeError:
    data = {}

if "${consumer}" not in data:
    raise SystemExit("ERROR: consumer not found in secrets file")

data.pop("${consumer}")
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

openssl enc -aes-256-cbc -pbkdf2 -in "${plaintext_tmp}" -out "${secrets_file}" "${pass_arg[@]}"
chmod 600 "${secrets_file}"

echo "PASS creds revoke: ${tenant}/${consumer}"
