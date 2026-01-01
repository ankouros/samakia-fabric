#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

makefile="${FABRIC_REPO_ROOT}/Makefile"
out_json="${FABRIC_REPO_ROOT}/ops/docs/operator-targets.json"

if [[ ! -f "${makefile}" ]]; then
  echo "Makefile not found at ${makefile}" >&2
  exit 1
fi

OUT_JSON="${out_json}" python3 - <<'PY'
import json
import os
import re
import sys
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])
makefile = root / "Makefile"
out_json = os.environ.get("OUT_JSON")
if not out_json:
    print("OUT_JSON not set", file=sys.stderr)
    sys.exit(1)

include = re.compile(r"^(phase[0-9]+|policy\.|ha\.|consumers\.|tenants\.|substrate\.|image\.|shared\..*\.accept$|dns\.|minio\.|tf\.)")
target_re = re.compile(r"^([A-Za-z0-9][A-Za-z0-9_.-]*)\s*:")

targets = set()
for line in makefile.read_text(encoding="utf-8").splitlines():
    if line.startswith("#") or line.startswith(".") or not line.strip():
        continue
    if ":=" in line or "?=" in line or "+=" in line:
        continue
    match = target_re.match(line)
    if not match:
        continue
    name = match.group(1)
    if include.match(name):
        targets.add(name)

with open(out_json, "w", encoding="utf-8") as fh:
    json.dump(sorted(targets), fh, indent=2)
    fh.write("\n")
PY
