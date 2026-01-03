#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

if [[ -z "${DRIFT_PATH:-}" || -z "${OUT_PATH:-}" ]]; then
  echo "ERROR: DRIFT_PATH and OUT_PATH are required" >&2
  exit 2
fi

python3 - "${DRIFT_PATH}" "${OUT_PATH}" <<'PY'
import json
import sys
from pathlib import Path

drift_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])

payload = json.loads(drift_path.read_text())

drift = payload.get("drift", {})
capacity = payload.get("capacity", {})

result = {
    "status": "PASS",
    "reasons": [],
}

if drift.get("available"):
    status = drift.get("status")
    klass = drift.get("class")
    if status and status != "PASS":
        result["status"] = "FAIL"
        result["reasons"].append(f"drift:{status}")
    if klass and klass not in {"none", "unknown"}:
        result["status"] = "FAIL"
        result["reasons"].append(f"drift_class:{klass}")

if capacity.get("available"):
    status = capacity.get("status")
    if status == "FAIL":
        result["status"] = "FAIL"
        result["reasons"].append("capacity:FAIL")
    violations = capacity.get("violations", [])
    if violations:
        result["status"] = "FAIL"
        result["reasons"].append("capacity:violations")

out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
PY
