#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  file.sh <command> [args]

Commands:
  get <key> [field]       Fetch a secret value (stdout)
  list [path]             List available keys (no values)
  doctor                  Show backend configuration (no secrets)
  put <key> <json_file>   Store secret object from JSON file
  put <key> -             Store secret object from stdin

Configuration:
  SECRETS_FILE           Encrypted JSON file path (default: ~/.config/samakia-fabric/secrets.enc)
  SECRETS_PASSPHRASE     Passphrase (env)
  SECRETS_PASSPHRASE_FILE Passphrase file path
EOT
}

cmd="${1:-}"
shift $(( $# >= 1 ? 1 : $# ))

if [[ -z "${cmd}" || "${cmd}" == "-h" || "${cmd}" == "--help" ]]; then
  usage
  exit 0
fi

secrets_file="${SECRETS_FILE:-${HOME}/.config/samakia-fabric/secrets.enc}"

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
    echo "{}"
    return
  fi
  openssl enc -d -aes-256-cbc -pbkdf2 -in "${secrets_file}" "${pass_arg[@]}"
}

encrypt() {
  require_passphrase
  local tmp_file
  tmp_file="${secrets_file}.tmp"
  openssl enc -aes-256-cbc -pbkdf2 -in /dev/stdin -out "${tmp_file}" "${pass_arg[@]}"
  mv "${tmp_file}" "${secrets_file}"
}

case "${cmd}" in
  get|list|doctor)
    exec bash "${FABRIC_REPO_ROOT}/ops/secrets/secrets-file.sh" "${cmd}" "$@"
    ;;
  put)
    key="${1:-}"
    src="${2:-}"
    if [[ -z "${key}" || -z "${src}" ]]; then
      echo "ERROR: put requires <key> <json_file|->" >&2
      exit 2
    fi
    if [[ "${src}" == "-" ]]; then
      input_json="$(cat)"
    else
      if [[ ! -f "${src}" ]]; then
        echo "ERROR: input file not found: ${src}" >&2
        exit 2
      fi
      input_json="$(cat "${src}")"
    fi

    tmp_decrypt="$(mktemp)"
    trap 'rm -f "${tmp_decrypt}"' EXIT
    decrypt > "${tmp_decrypt}"
    INPUT_JSON="${input_json}"
    export INPUT_JSON
    python3 - "${key}" "${tmp_decrypt}" <<'PY' | encrypt
import json
import os
import sys

key = sys.argv[1]
raw = open(sys.argv[2], "r", encoding="utf-8").read()
input_json = os.environ.get("INPUT_JSON", "")

if not input_json.strip():
    print("ERROR: input JSON is empty", file=sys.stderr)
    sys.exit(2)

try:
    incoming = json.loads(input_json)
except json.JSONDecodeError as exc:
    print(f"ERROR: input JSON invalid: {exc}", file=sys.stderr)
    sys.exit(2)

if not isinstance(incoming, dict):
    print("ERROR: input JSON must be an object", file=sys.stderr)
    sys.exit(2)

data = {}
if raw.strip():
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"ERROR: existing secrets file is not valid JSON: {exc}", file=sys.stderr)
        sys.exit(2)

data[key] = incoming
print(json.dumps(data, sort_keys=True))
PY
    unset INPUT_JSON
    rm -f "${tmp_decrypt}"
    trap - EXIT
    ;;
  *)
    echo "ERROR: unsupported command: ${cmd}" >&2
    usage
    exit 2
    ;;
esac
