#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

input_path="${FABRIC_REPO_ROOT}/hardening/checklist.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      input_path="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

INPUT_PATH="${input_path}" python3 - <<'PY'
import json
import os
import sys

input_path = os.environ.get("INPUT_PATH")
if not input_path:
    raise SystemExit("INPUT_PATH must be set")

with open(input_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

hard_fail = []
soft_fail = []
for category in data.get("categories", []):
    for check in category.get("checks", []):
        status = check.get("status")
        severity = check.get("severity")
        if status == "FAIL" and severity == "hard":
            hard_fail.append(check)
        elif status == "WARN" and severity == "soft":
            soft_fail.append(check)
        elif status == "FAIL" and severity == "soft":
            soft_fail.append(check)

summary = {
    "phase": data.get("phase"),
    "generated_at": data.get("generated_at"),
    "hard_failures": len(hard_fail),
    "soft_failures": len(soft_fail),
    "blocking": [check["id"] for check in hard_fail],
    "status": "PASS" if not hard_fail else "FAIL",
}

print(json.dumps(summary, indent=2, sort_keys=True))
if hard_fail:
    sys.exit(1)
PY
