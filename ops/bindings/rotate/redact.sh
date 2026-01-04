#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

usage() {
  cat >&2 <<'EOT'
Usage:
  redact.sh --in <cutover.yml> --out <cutover.yml.redacted>

Notes:
  - Redacts secret-like keys while preserving secret_ref identifiers.
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

if [[ -z "${in_file}" || -z "${out_file}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${in_file}" ]]; then
  echo "ERROR: input file not found: ${in_file}" >&2
  exit 2
fi

IN_FILE="${in_file}" OUT_FILE="${out_file}" python3 - <<'PY'
import os
import re
from pathlib import Path
import yaml

in_path = Path(os.environ["IN_FILE"])
out_path = Path(os.environ["OUT_FILE"])

sensitive_key = re.compile(r"(password|token|api_key|access_key|private_key|secret_value)", re.IGNORECASE)
allow_keys = {"secret_ref", "old_secret_ref", "new_secret_ref"}


def redact(obj):
    if isinstance(obj, dict):
        out = {}
        for key, value in obj.items():
            if key in allow_keys:
                out[key] = value
            elif sensitive_key.search(str(key)):
                out[key] = "<redacted>"
            else:
                out[key] = redact(value)
        return out
    if isinstance(obj, list):
        return [redact(value) for value in obj]
    return obj

payload = yaml.safe_load(in_path.read_text())
redacted = redact(payload)

out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(yaml.safe_dump(redacted, sort_keys=True))
PY
