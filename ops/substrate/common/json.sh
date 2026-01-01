#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

write_json() {
  local dest="$1"
  local payload="$2"
  python3 - <<PY
import json
from pathlib import Path

Path("${dest}").write_text(json.dumps(${payload}, indent=2, sort_keys=True) + "\n")
PY
}
