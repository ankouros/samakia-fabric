#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


input="${1:-}"
output="${2:-}"

if [[ -z "${input}" || -z "${output}" ]]; then
  echo "usage: redaction.sh <input-json> <output-json>" >&2
  exit 1
fi

if [[ ! -f "${input}" ]]; then
  echo "ERROR: input not found: ${input}" >&2
  exit 1
fi

INPUT="${input}" OUTPUT="${output}" python3 - <<'PY'
import json
import os
import re
from pathlib import Path

secret_pattern = re.compile(r"(password|token|secret|BEGIN (RSA|OPENSSH)|AKIA[0-9A-Z]{12,})", re.IGNORECASE)


def redact(value, allow_secret_ref=False):
    if isinstance(value, dict):
        result = {}
        for key, val in value.items():
            if key == "secret_ref":
                result[key] = val
            else:
                result[key] = redact(val)
        return result
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, str):
        if allow_secret_ref:
            return value
        if secret_pattern.search(value):
            return "<redacted>"
    return value

path = Path(os.environ["INPUT"])
output = Path(os.environ["OUTPUT"])

data = json.loads(path.read_text())
redacted = redact(data)
output.write_text(json.dumps(redacted, indent=2, sort_keys=True) + "\n")
PY
