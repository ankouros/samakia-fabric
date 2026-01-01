#!/usr/bin/env bash
set -euo pipefail

input="${1:-}"
output="${2:-}"

if [[ -z "${input}" || -z "${output}" ]]; then
  echo "usage: normalize-json.sh <input> <output>" >&2
  exit 1
fi

if [[ ! -f "${input}" ]]; then
  echo "ERROR: input not found: ${input}" >&2
  exit 1
fi

INPUT="${input}" OUTPUT="${output}" python3 - <<'PY'
import json
import os
from pathlib import Path

src = Path(os.environ["INPUT"])
dst = Path(os.environ["OUTPUT"])

data = json.loads(src.read_text())
dst.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
