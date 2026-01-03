#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  phase12-readiness-redact.sh <input> <output>

Redacts secret-like keys in JSON/YAML files. Non-structured files are copied as-is.
EOT
}

input_path="${1:-}"
output_path="${2:-}"

if [[ -z "${input_path}" || -z "${output_path}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${input_path}" ]]; then
  echo "ERROR: input file not found: ${input_path}" >&2
  exit 1
fi

ext="${input_path##*.}"
case "${ext}" in
  json|yml|yaml)
    INPUT_PATH="${input_path}" OUTPUT_PATH="${output_path}" python3 - <<'PY'
import json
import os
from pathlib import Path

try:
    import yaml
except ImportError as exc:
    raise SystemExit("ERROR: PyYAML required for redaction") from exc

input_path = Path(os.environ["INPUT_PATH"])
output_path = Path(os.environ["OUTPUT_PATH"])

ext = input_path.suffix.lower()

redact_keys = {
    "secret", "secret_ref", "secret_key", "access_key", "token", "password", "api_key", "apikey",
}


def should_redact(key: str) -> bool:
    key_lower = key.lower()
    if key_lower in redact_keys:
        return True
    if "secret" in key_lower or "token" in key_lower or "password" in key_lower:
        return True
    return False


def redact(obj):
    if isinstance(obj, dict):
        redacted = {}
        for key, value in obj.items():
            if isinstance(key, str) and should_redact(key):
                redacted[key] = "<redacted>"
            else:
                redacted[key] = redact(value)
        return redacted
    if isinstance(obj, list):
        return [redact(item) for item in obj]
    return obj

if ext == ".json":
    payload = json.loads(input_path.read_text())
    output_path.write_text(json.dumps(redact(payload), indent=2, sort_keys=True) + "\n")
else:
    payload = yaml.safe_load(input_path.read_text())
    output_path.write_text(yaml.safe_dump(redact(payload), sort_keys=True))
PY
    ;;
  *)
    cp "${input_path}" "${output_path}"
    ;;
esac
