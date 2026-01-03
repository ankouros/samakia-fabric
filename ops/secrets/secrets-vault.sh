#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  secrets-vault.sh <command> [args]

Commands:
  get <key> [field]   Fetch a secret value (stdout)
  list [path]         List available keys (no values)
  doctor              Show backend configuration (no secrets)

Configuration:
  VAULT_ADDR        Vault HTTPS URL (required)
  VAULT_TOKEN       Vault token (required)
  VAULT_NAMESPACE   Optional namespace
  VAULT_CACERT      Optional CA bundle path
  VAULT_KV_MOUNT    KV v2 mount (default: secret)

Notes:
  - Uses KV v2: /v1/<mount>/data/<key> and /v1/<mount>/metadata/<path>
  - Token is never printed.
EOT
}

cmd="${1:-}"
shift $(( $# >= 1 ? 1 : $# ))

if [[ -z "${cmd}" || "${cmd}" == "-h" || "${cmd}" == "--help" ]]; then
  usage
  exit 0
fi

vault_addr="${VAULT_ADDR:-}"
vault_token="${VAULT_TOKEN:-}"
vault_mount="${VAULT_KV_MOUNT:-secret}"

if [[ -z "${vault_addr}" || -z "${vault_token}" ]]; then
  echo "ERROR: VAULT_ADDR and VAULT_TOKEN must be set" >&2
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl not found (required for Vault backend)" >&2
  exit 1
fi

if [[ "${vault_addr}" != https://* ]]; then
  echo "ERROR: VAULT_ADDR must be https:// (strict TLS required)" >&2
  exit 2
fi

curl_args=(--fail --silent --show-error --location)
if [[ -n "${VAULT_CACERT:-}" ]]; then
  if [[ ! -f "${VAULT_CACERT}" ]]; then
    echo "ERROR: VAULT_CACERT not found: ${VAULT_CACERT}" >&2
    exit 2
  fi
  curl_args+=(--cacert "${VAULT_CACERT}")
fi

if [[ -n "${VAULT_NAMESPACE:-}" ]]; then
  curl_args+=(-H "X-Vault-Namespace: ${VAULT_NAMESPACE}")
fi

curl_args+=(-H "X-Vault-Token: ${vault_token}")

case "${cmd}" in
  doctor)
    echo "Backend: vault"
    echo "VAULT_ADDR: ${vault_addr}"
    echo "VAULT_NAMESPACE: ${VAULT_NAMESPACE:-<none>}"
    echo "VAULT_KV_MOUNT: ${vault_mount}"
    if [[ -n "${VAULT_CACERT:-}" ]]; then
      echo "VAULT_CACERT: ${VAULT_CACERT}"
    else
      echo "VAULT_CACERT: <system trust>"
    fi
    echo "Token: configured"
    ;;
  list)
    path="${1:-}"
    url="${vault_addr}/v1/${vault_mount}/metadata"
    if [[ -n "${path}" ]]; then
      url+="/${path}"
    fi
    url+="?list=true"
    tmp="$(mktemp)"
    curl "${curl_args[@]}" "${url}" > "${tmp}"
    python3 - "${tmp}" <<'PY'
import json
import sys

try:
    data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
except json.JSONDecodeError as exc:
    print(f"ERROR: invalid Vault response: {exc}", file=sys.stderr)
    sys.exit(2)

keys = data.get("data", {}).get("keys")
if not isinstance(keys, list):
    print("ERROR: Vault list response missing keys", file=sys.stderr)
    sys.exit(2)

for key in sorted(keys):
    print(key)
PY
    rm -f "${tmp}"
    ;;
  get)
    key="${1:-}"
    field="${2:-}"
    if [[ -z "${key}" ]]; then
      echo "ERROR: get requires <key>" >&2
      exit 2
    fi
    url="${vault_addr}/v1/${vault_mount}/data/${key}"
    tmp="$(mktemp)"
    curl "${curl_args[@]}" "${url}" > "${tmp}"
    python3 - "${field}" "${tmp}" <<'PY'
import json
import sys

field = sys.argv[1]

try:
    payload = json.load(open(sys.argv[2], "r", encoding="utf-8"))
except json.JSONDecodeError as exc:
    print(f"ERROR: invalid Vault response: {exc}", file=sys.stderr)
    sys.exit(2)

value = payload.get("data", {}).get("data")
if not isinstance(value, dict):
    print("ERROR: Vault response missing data", file=sys.stderr)
    sys.exit(2)

if field:
    if field not in value:
        print(f"ERROR: field not found: {field}", file=sys.stderr)
        sys.exit(2)
    value = value[field]

if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
    rm -f "${tmp}"
    ;;
  *)
    echo "ERROR: unsupported command: ${cmd}" >&2
    usage
    exit 2
    ;;
esac
