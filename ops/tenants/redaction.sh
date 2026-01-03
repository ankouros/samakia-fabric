#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


input="${1:-}"
if [[ -z "${input}" ]]; then
  echo "usage: redaction.sh <file>" >&2
  exit 1
fi

if [[ ! -f "${input}" ]]; then
  echo "ERROR: file not found: ${input}" >&2
  exit 1
fi

INPUT="${input}" python3 - <<'PY'
import json
import os
import re
import sys

secret_pattern = re.compile(
    r"(password|token|secret|BEGIN (RSA|OPENSSH)|AKIA[0-9A-Z]{12,})",
    re.IGNORECASE,
)


def scan(value, path="$", allow_secret_ref=False):
    if isinstance(value, dict):
        for key, val in value.items():
            if key == "secret_ref":
                scan(val, f"{path}.{key}", allow_secret_ref=True)
            else:
                scan(val, f"{path}.{key}", allow_secret_ref=False)
    elif isinstance(value, list):
        for idx, item in enumerate(value):
            scan(item, f"{path}[{idx}]", allow_secret_ref=allow_secret_ref)
    elif isinstance(value, str):
        if allow_secret_ref:
            return
        if secret_pattern.search(value):
            print(f"ERROR: secret-like value in {path}", file=sys.stderr)
            sys.exit(1)


path = os.environ["INPUT"]
try:
    data = json.loads(open(path, "r", encoding="utf-8").read())
except json.JSONDecodeError as exc:
    print(f"ERROR: invalid JSON in {path} ({exc})", file=sys.stderr)
    sys.exit(1)

scan(data)
print(f"PASS: redaction check {path}")
PY
