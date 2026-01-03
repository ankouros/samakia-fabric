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

inp = Path(sys.argv[1])
out = Path(sys.argv[2])

alert = json.loads(inp.read_text())

payload = {
    "title": alert.get("summary") or "Alert",
    "severity": alert.get("severity_mapped") or alert.get("severity"),
    "tenant": alert.get("tenant"),
    "workload": alert.get("workload"),
    "signal_type": alert.get("signal_type"),
    "environment": alert.get("env"),
    "timestamp_utc": alert.get("timestamp_utc"),
    "evidence_ref": alert.get("evidence_ref"),
}

out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
