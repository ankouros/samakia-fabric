#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${IN_PATH:-}" || -z "${OUT_PATH:-}" ]]; then
  echo "ERROR: IN_PATH and OUT_PATH are required" >&2
  exit 2
fi

python3 - "${IN_PATH}" "${OUT_PATH}" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dest = Path(sys.argv[2])

sensitive_keys = {"secret_ref", "secret", "token", "password", "authorization"}


def redact(obj):
    if isinstance(obj, dict):
        out = {}
        for key, val in obj.items():
            if key in sensitive_keys:
                out[key] = "<redacted>"
            else:
                out[key] = redact(val)
        return out
    if isinstance(obj, list):
        return [redact(item) for item in obj]
    return obj

payload = json.loads(src.read_text())
redacted = redact(payload)
dest.write_text(json.dumps(redacted, indent=2, sort_keys=True) + "\n")
PY
