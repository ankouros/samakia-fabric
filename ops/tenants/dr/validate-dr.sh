#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

TENANTS_ROOT="${FABRIC_REPO_ROOT}/contracts/tenants/examples"
TESTCASES_FILE="${FABRIC_REPO_ROOT}/ops/tenants/dr/testcases.yml"

if [[ ! -d "${TENANTS_ROOT}" ]]; then
  echo "ERROR: tenants examples not found: ${TENANTS_ROOT}" >&2
  exit 1
fi

if [[ ! -f "${TESTCASES_FILE}" ]]; then
  echo "ERROR: DR testcase registry missing: ${TESTCASES_FILE}" >&2
  exit 1
fi

TENANTS_ROOT="${TENANTS_ROOT}" TESTCASES_FILE="${TESTCASES_FILE}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["TENANTS_ROOT"])
registry = Path(os.environ["TESTCASES_FILE"])

errors = []

try:
    data = json.loads(registry.read_text())
except json.JSONDecodeError as exc:
    print(f"ERROR: invalid JSON in {registry}: {exc}", file=sys.stderr)
    sys.exit(2)

cases = {item.get("id") for item in data.get("testcases", []) if isinstance(item, dict)}
if not cases:
    errors.append(f"{registry}: no testcases defined")

for enabled in root.rglob("consumers/**/enabled.yml"):
    try:
        binding = json.loads(enabled.read_text())
    except json.JSONDecodeError as exc:
        errors.append(f"{enabled}: invalid JSON ({exc})")
        continue
    spec = binding.get("spec", {})
    dr = spec.get("dr_testcases", [])
    restore = spec.get("restore_testcases", [])
    if not isinstance(dr, list) or not dr:
        errors.append(f"{enabled}: dr_testcases must be a non-empty list")
    else:
        unknown = [case for case in dr if case not in cases]
        if unknown:
            errors.append(f"{enabled}: unknown dr_testcases {unknown}")
    if not isinstance(restore, list) or not restore:
        errors.append(f"{enabled}: restore_testcases must be a non-empty list")
    else:
        unknown = [case for case in restore if case not in cases]
        if unknown:
            errors.append(f"{enabled}: unknown restore_testcases {unknown}")

if errors:
    for err in errors:
        print(f"FAIL dr: {err}")
    sys.exit(1)

for enabled in root.rglob("consumers/**/enabled.yml"):
    print(f"PASS dr: {enabled}")
PY
