#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ms_to_seconds() {
  local ms="$1"
  if [[ -z "${ms}" ]]; then
    echo ""
    return
  fi
  python3 - "${ms}" <<'PY'
import sys
try:
    ms = float(sys.argv[1])
except ValueError:
    sys.exit(2)
if ms <= 0:
    sys.exit(2)
print(f"{ms/1000.0:.3f}")
PY
}
