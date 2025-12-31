#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

index_path="${FABRIC_REPO_ROOT}/ops/scripts/safe-index.yml"

if [[ ! -f "${index_path}" ]]; then
  echo "ERROR: safe-index file missing: ${index_path}" >&2
  exit 1
fi

python3 - "${index_path}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except Exception as exc:
    print(f"ERROR: cannot parse safe-index: {exc}", file=sys.stderr)
    sys.exit(1)

if data.get("version") != 1:
    print("ERROR: safe-index version must be 1", file=sys.stderr)
    sys.exit(1)

allowlist = data.get("allowlist")
if not isinstance(allowlist, list) or not allowlist:
    print("ERROR: safe-index allowlist must be a non-empty list", file=sys.stderr)
    sys.exit(1)

required = {"name", "type", "command", "description", "inputs", "outputs", "evidence"}
for item in allowlist:
    if not isinstance(item, dict):
        print("ERROR: allowlist entry is not an object", file=sys.stderr)
        sys.exit(1)
    missing = required - set(item.keys())
    if missing:
        print(f"ERROR: allowlist entry missing keys: {sorted(missing)}", file=sys.stderr)
        sys.exit(1)
    if item.get("type") not in {"read-only", "execute-guarded"}:
        print("ERROR: invalid type in allowlist", file=sys.stderr)
        sys.exit(1)
    if not item.get("command"):
        print("ERROR: command is empty", file=sys.stderr)
        sys.exit(1)

print("OK: safe-index validated")
PY
