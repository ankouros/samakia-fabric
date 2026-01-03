#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  redact.sh [--in <file>] [--out <file>]

Redacts sensitive-looking values in JSON objects.
EOT
}

in_file=""
out_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --in)
      in_file="$2"
      shift 2
      ;;
    --out)
      out_file="$2"
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

if [[ -n "${in_file}" ]]; then
  if [[ ! -f "${in_file}" ]]; then
    echo "ERROR: input file not found: ${in_file}" >&2
    exit 2
  fi
  input_json="$(cat "${in_file}")"
else
  input_json="$(cat)"
fi

tmp="$(mktemp)"
printf '%s' "${input_json}" > "${tmp}"
redacted_json="$(python3 - "${tmp}" <<'PY'
import json
import re
import sys

raw = open(sys.argv[1], "r", encoding="utf-8").read()
if not raw.strip():
    print("{}")
    sys.exit(0)

try:
    data = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"ERROR: invalid JSON: {exc}", file=sys.stderr)
    sys.exit(2)

sensitive_key = re.compile(r"(password|secret|token|api_key|key|passphrase|access_key)", re.IGNORECASE)


def redact(obj):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if sensitive_key.search(str(k)):
                out[k] = "[REDACTED]"
            else:
                out[k] = redact(v)
        return out
    if isinstance(obj, list):
        return [redact(v) for v in obj]
    return obj

print(json.dumps(redact(data), indent=2, sort_keys=True))
PY
)"
rm -f "${tmp}"

if [[ -n "${out_file}" ]]; then
  printf '%s\n' "${redacted_json}" > "${out_file}"
else
  printf '%s\n' "${redacted_json}"
fi
