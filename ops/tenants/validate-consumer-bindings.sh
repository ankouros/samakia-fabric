#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

TENANTS_ROOT="${FABRIC_REPO_ROOT}/contracts/tenants"
TESTCASES_FILE="${FABRIC_REPO_ROOT}/contracts/tenants/_schema/dr-testcases.yml"

if [[ ! -d "${TENANTS_ROOT}" ]]; then
  echo "ERROR: tenants directory not found: ${TENANTS_ROOT}" >&2
  exit 1
fi

if [[ ! -f "${TESTCASES_FILE}" ]]; then
  echo "ERROR: dr testcases list missing: ${TESTCASES_FILE}" >&2
  exit 1
fi

TENANTS_ROOT="${TENANTS_ROOT}" TESTCASES_FILE="${TESTCASES_FILE}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

tenants_root = Path(os.environ["TENANTS_ROOT"])
testcases_path = Path(os.environ["TESTCASES_FILE"])

errors = []


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        errors.append(f"{path}: invalid JSON ({exc})")
        return None


testcases = load_json(testcases_path)
if not isinstance(testcases, list) or not testcases:
    errors.append(f"{testcases_path}: invalid or empty testcase list")
    testcases = []

for ready in tenants_root.rglob("consumers/**/ready.yml"):
    binding = load_json(ready)
    if not binding:
        continue
    spec = binding.get("spec", {})
    if spec.get("ha_ready") is not True:
        errors.append(f"{ready}: ha_ready must be true")
    dr = spec.get("dr_testcases", [])
    if not isinstance(dr, list) or not dr:
        errors.append(f"{ready}: dr_testcases must be a non-empty list")
    else:
        unknown = [case for case in dr if case not in testcases]
        if unknown:
            errors.append(f"{ready}: unknown dr_testcases {unknown}")

if errors:
    for err in errors:
        print(f"FAIL bindings: {err}")
    sys.exit(1)

for ready in tenants_root.rglob("consumers/**/ready.yml"):
    print(f"PASS bindings: {ready}")
PY
