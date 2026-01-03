#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


ops_script="${FABRIC_REPO_ROOT}/ops/ai/ops.sh"
if [[ ! -x "${ops_script}" ]]; then
  echo "ERROR: ops.sh missing or not executable: ${ops_script}" >&2
  exit 1
fi

OPS_SCRIPT="${ops_script}" python3 - <<'PY'
import os
import re
import sys
from pathlib import Path

path = Path(os.environ["OPS_SCRIPT"])
text = path.read_text(encoding="utf-8").splitlines()

case_block = False
labels = []
for line in text:
    if "case" in line and "command" in line:
        case_block = True
        continue
    if case_block:
        if line.strip().startswith("esac"):
            break
        match = re.match(r"\s*([A-Za-z0-9_.|/-]+)\)", line)
        if match:
            labels.extend(match.group(1).split("|"))

allowed = {
    "doctor",
    "index.preview",
    "index.offline",
    "analyze.plan",
    "analyze.run",
    "status",
}
ignore = {"-h", "--help", "help", "*", ""}

commands = {label for label in labels if label not in ignore}
missing = allowed - commands
extra = commands - allowed

if missing or extra:
    if missing:
        print(f"ERROR: missing ops.sh commands: {sorted(missing)}", file=sys.stderr)
    if extra:
        print(f"ERROR: unexpected ops.sh commands: {sorted(extra)}", file=sys.stderr)
    sys.exit(1)

print("PASS: ops.sh commands are locked")
PY
