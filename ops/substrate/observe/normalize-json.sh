#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


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
