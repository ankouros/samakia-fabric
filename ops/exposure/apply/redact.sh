#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

if [[ $# -ne 2 ]]; then
  echo "usage: redact.sh <input-json> <output-json>" >&2
  exit 2
fi

input="$1"
output="$2"

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
bearer_pattern = re.compile(r"bearer\s+[a-z0-9\-\._]+", re.IGNORECASE)
dsn_scheme_pattern = re.compile(r"^(postgres|postgresql|mysql|mariadb|amqp|redis|rediss|mongodb|rabbitmq|qdrant)://", re.IGNORECASE)

sensitive_keys = {"password", "token", "secret", "dsn", "connection_string"}


def has_creds(value: str) -> bool:
    if "@" not in value:
        return False
    prefix = value.split("@", 1)[0]
    return ":" in prefix


def redact(value, key_name="", allow_secret_ref=False):
    if isinstance(value, dict):
        result = {}
        for key, val in value.items():
            if key == "secret_ref":
                result[key] = val
            else:
                result[key] = redact(val, key_name=key, allow_secret_ref=False)
        return result
    if isinstance(value, list):
        return [redact(item, key_name=key_name, allow_secret_ref=allow_secret_ref) for item in value]
    if isinstance(value, str):
        if allow_secret_ref:
            return value
        if key_name.lower() in sensitive_keys:
            return "<redacted>"
        if bearer_pattern.search(value):
            return "<redacted>"
        if secret_pattern.search(value):
            return "<redacted>"
        if dsn_scheme_pattern.search(value) and has_creds(value):
            return "<redacted>"
    return value

path = Path(os.environ["INPUT"])
output = Path(os.environ["OUTPUT"])

data = json.loads(path.read_text())
redacted = redact(data)
output.write_text(json.dumps(redacted, indent=2, sort_keys=True) + "\n")
PY
