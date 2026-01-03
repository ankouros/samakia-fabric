#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  secrets-file.sh <command> [args]

Commands:
  get <key> [field]   Fetch a secret value (stdout)
  list [path]         List available keys (no values)
  doctor              Show backend configuration (no secrets)

Configuration:
  SECRETS_FILE                Path to encrypted JSON file (default: ~/.config/samakia-fabric/secrets.enc)
  SECRETS_PASSPHRASE           Passphrase (env)
  SECRETS_PASSPHRASE_FILE      Passphrase file path

Notes:
  - File content is JSON (object). Keys are retrieved by <key> and optional [field].
  - Passphrase is never printed.
EOT
}

cmd="${1:-}"
shift $(( $# >= 1 ? 1 : $# ))

if [[ -z "${cmd}" || "${cmd}" == "-h" || "${cmd}" == "--help" ]]; then
  usage
  exit 0
fi

secrets_file="${SECRETS_FILE:-${HOME}/.config/samakia-fabric/secrets.enc}"

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl not found (required for secrets file backend)" >&2
  exit 1
fi

pass_arg=()
if [[ -n "${SECRETS_PASSPHRASE_FILE:-}" ]]; then
  if [[ ! -f "${SECRETS_PASSPHRASE_FILE}" ]]; then
    echo "ERROR: SECRETS_PASSPHRASE_FILE not found: ${SECRETS_PASSPHRASE_FILE}" >&2
    exit 2
  fi
  pass_arg=( -pass "file:${SECRETS_PASSPHRASE_FILE}" )
elif [[ -n "${SECRETS_PASSPHRASE:-}" ]]; then
  pass_arg=( -pass env:SECRETS_PASSPHRASE )
fi

require_passphrase() {
  if [[ ${#pass_arg[@]} -eq 0 ]]; then
    echo "ERROR: passphrase not set (use SECRETS_PASSPHRASE or SECRETS_PASSPHRASE_FILE)" >&2
    exit 2
  fi
}

decrypt() {
  require_passphrase
  if [[ ! -f "${secrets_file}" ]]; then
    echo "ERROR: secrets file not found: ${secrets_file}" >&2
    exit 2
  fi
  openssl enc -d -aes-256-cbc -pbkdf2 -in "${secrets_file}" "${pass_arg[@]}"
}

case "${cmd}" in
  doctor)
    echo "Backend: file"
    echo "Secrets file: ${secrets_file}"
    if [[ ${#pass_arg[@]} -gt 0 ]]; then
      echo "Passphrase: configured"
    else
      echo "Passphrase: missing"
    fi
    if [[ -f "${secrets_file}" ]]; then
      echo "File present: yes"
    else
      echo "File present: no"
    fi
    ;;
  list)
    path="${1:-}"
    tmp="$(mktemp)"
    decrypt > "${tmp}"
    python3 - "${path}" "${tmp}" <<'PY'
import json
import sys

path = sys.argv[1].strip()
raw = open(sys.argv[2], "r", encoding="utf-8").read()
if not raw.strip():
    print("ERROR: decrypted secrets file is empty", file=sys.stderr)
    sys.exit(2)

try:
    data = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"ERROR: secrets file is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(2)

node = data
if path:
    for part in path.split("/"):
        if part == "":
            continue
        if not isinstance(node, dict) or part not in node:
            print(f"ERROR: path not found: {path}", file=sys.stderr)
            sys.exit(2)
        node = node[part]

if isinstance(node, dict):
    for key in sorted(node.keys()):
        print(key)
else:
    print("ERROR: path does not resolve to an object", file=sys.stderr)
    sys.exit(2)
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
    tmp="$(mktemp)"
    decrypt > "${tmp}"
    python3 - "${key}" "${field}" "${tmp}" <<'PY'
import json
import sys

key = sys.argv[1]
field = sys.argv[2]
raw = open(sys.argv[3], "r", encoding="utf-8").read()

if not raw.strip():
    print("ERROR: decrypted secrets file is empty", file=sys.stderr)
    sys.exit(2)

try:
    data = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"ERROR: secrets file is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(2)

if key not in data:
    print(f"ERROR: key not found: {key}", file=sys.stderr)
    sys.exit(2)

value = data[key]
if field:
    if not isinstance(value, dict):
        print(f"ERROR: key '{key}' is not an object", file=sys.stderr)
        sys.exit(2)
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
