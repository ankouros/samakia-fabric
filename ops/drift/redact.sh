#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


input="${1:-}"
output="${2:-}"
if [[ -z "${input}" || -z "${output}" ]]; then
  echo "usage: redact.sh <input.json> <output.json>" >&2
  exit 2
fi

python3 - "${input}" "${output}" <<'PY'
import json
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

patterns = [
    re.compile(r"password", re.IGNORECASE),
    re.compile(r"token", re.IGNORECASE),
    re.compile(r"secret", re.IGNORECASE),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"BEGIN (RSA|OPENSSH) PRIVATE KEY"),
]

allowed_refs = re.compile(r"^(tenants/|vault://)")


def scrub(value):
    if isinstance(value, str):
        if allowed_refs.search(value):
            return value
        for pattern in patterns:
            if pattern.search(value):
                return "<redacted>"
        return value
    if isinstance(value, list):
        return [scrub(v) for v in value]
    if isinstance(value, dict):
        return {k: scrub(v) for k, v in value.items()}
    return value

payload = json.loads(src.read_text())
redacted = scrub(payload)
dst.write_text(json.dumps(redacted, sort_keys=True, indent=2) + "\n")
PY
