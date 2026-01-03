#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


TENANT="${TENANT:-}"
if [[ -z "${TENANT}" ]]; then
  echo "ERROR: TENANT is required" >&2
  exit 2
fi

python3 - "${TENANT}" <<'PY'
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])

tenant = sys.argv[1]
verify_root = root / "evidence" / "bindings-verify" / tenant

result = {
    "tenant": tenant,
    "status": "UNKNOWN",
    "run_id": None,
    "issues": [],
}

if not verify_root.exists():
    result["issues"].append("bindings-verify evidence not found")
    print(json.dumps(result, sort_keys=True, indent=2))
    sys.exit(0)

runs = sorted([p for p in verify_root.iterdir() if p.is_dir()])
if not runs:
    result["issues"].append("no bindings-verify runs present")
    print(json.dumps(result, sort_keys=True, indent=2))
    sys.exit(0)

latest = runs[-1]
results_path = latest / "results.json"
if not results_path.exists():
    result["issues"].append("results.json missing in latest verify run")
    print(json.dumps(result, sort_keys=True, indent=2))
    sys.exit(0)

try:
    payload = json.loads(results_path.read_text())
except json.JSONDecodeError:
    result["issues"].append("results.json unreadable")
    print(json.dumps(result, sort_keys=True, indent=2))
    sys.exit(0)

statuses = [entry.get("status", "UNKNOWN") for entry in payload]
status = "PASS"
if any(s == "FAIL" for s in statuses):
    status = "FAIL"
elif any(s == "WARN" for s in statuses):
    status = "WARN"

result["status"] = status
result["run_id"] = latest.name
result["results_count"] = len(payload)

if status != "PASS":
    failed = [entry.get("workload_id") for entry in payload if entry.get("status") in {"FAIL", "WARN"}]
    result["issues"].append({"workloads": [w for w in failed if w]})

print(json.dumps(result, sort_keys=True, indent=2))
PY
