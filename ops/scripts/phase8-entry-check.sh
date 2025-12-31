#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE8_ENTRY_CHECKLIST.md"

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

pass() {
  local label="$1"
  local cmd="$2"
  {
    echo "- ${label}"
    echo "  - Command: ${cmd}"
    echo "  - Result: PASS"
  } >>"${out_file}"
}

fail() {
  local label="$1"
  local cmd="$2"
  local reason="$3"
  {
    echo "- ${label}"
    echo "  - Command: ${cmd}"
    echo "  - Result: FAIL"
    echo "  - Reason: ${reason}"
  } >>"${out_file}"
  exit 1
}

cat >"${out_file}" <<EOF_HEAD
# Phase 8 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE0_ACCEPTED.md"
  "acceptance/PHASE1_ACCEPTED.md"
  "acceptance/PHASE2_ACCEPTED.md"
  "acceptance/PHASE2_1_ACCEPTED.md"
  "acceptance/PHASE2_2_ACCEPTED.md"
  "acceptance/PHASE3_PART1_ACCEPTED.md"
  "acceptance/PHASE3_PART2_ACCEPTED.md"
  "acceptance/PHASE3_PART3_ACCEPTED.md"
  "acceptance/PHASE4_ACCEPTED.md"
  "acceptance/PHASE5_ACCEPTED.md"
  "acceptance/PHASE6_PART1_ACCEPTED.md"
  "acceptance/PHASE6_PART2_ACCEPTED.md"
  "acceptance/PHASE6_PART3_ACCEPTED.md"
  "acceptance/PHASE7_ACCEPTED.md"
)

for marker in "${markers[@]}"; do
  cmd="test -f ${marker}"
  if [[ -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
    pass "Acceptance marker present: ${marker}" "${cmd}"
  else
    fail "Acceptance marker present: ${marker}" "${cmd}" "missing marker"
  fi
done

if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
  fail "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md" "OPEN items found"
else
  pass "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md"
fi

if rg -n "ADR-0025" "${FABRIC_REPO_ROOT}/DECISIONS.md" >/dev/null 2>&1; then
  pass "ADR-0025 present" "rg -n \"ADR-0025\" DECISIONS.md"
else
  fail "ADR-0025 present" "rg -n \"ADR-0025\" DECISIONS.md" "missing ADR"
fi

schema="${FABRIC_REPO_ROOT}/contracts/images/vm/_schema/vm-image-contract.schema.json"
if [[ -f "${schema}" ]]; then
  pass "VM image contract schema present" "test -f contracts/images/vm/_schema/vm-image-contract.schema.json"
else
  fail "VM image contract schema present" "test -f contracts/images/vm/_schema/vm-image-contract.schema.json" "missing schema"
fi

contracts=(
  "contracts/images/vm/ubuntu-24.04/v1/image.yml"
  "contracts/images/vm/debian-12/v1/image.yml"
)

for contract in "${contracts[@]}"; do
  cmd="test -f ${contract}"
  if [[ -f "${FABRIC_REPO_ROOT}/${contract}" ]]; then
    pass "Contract present: ${contract}" "${cmd}"
  else
    fail "Contract present: ${contract}" "${cmd}" "missing contract"
  fi
done

if python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])

schema_path = root / "contracts/images/vm/_schema/vm-image-contract.schema.json"
contracts = [
    root / "contracts/images/vm/ubuntu-24.04/v1/image.yml",
    root / "contracts/images/vm/debian-12/v1/image.yml",
]

schema = json.loads(schema_path.read_text())


def err(msg):
    print(msg, file=sys.stderr)


def type_ok(value, expected):
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int)
    if expected == "boolean":
        return isinstance(value, bool)
    return True


def validate(data, schema_obj, path="$"):
    if "type" in schema_obj:
        if not type_ok(data, schema_obj["type"]):
            err(f"{path}: expected {schema_obj['type']}")
            return False
    if "const" in schema_obj:
        if data != schema_obj["const"]:
            err(f"{path}: expected const {schema_obj['const']}")
            return False
    if "enum" in schema_obj:
        if data not in schema_obj["enum"]:
            err(f"{path}: value {data} not in {schema_obj['enum']}")
            return False
    if schema_obj.get("type") == "object":
        required = schema_obj.get("required", [])
        for key in required:
            if key not in data:
                err(f"{path}: missing required key {key}")
                return False
        props = schema_obj.get("properties", {})
        for key, val in data.items():
            if key in props:
                if not validate(val, props[key], f"{path}.{key}"):
                    return False
    if schema_obj.get("type") == "array":
        item_schema = schema_obj.get("items")
        if item_schema is not None:
            for idx, item in enumerate(data):
                if not validate(item, item_schema, f"{path}[{idx}]"):
                    return False
    return True

ok = True
for contract in contracts:
    data = json.loads(contract.read_text())
    if not validate(data, schema, f"{contract.name}"):
        ok = False

if not ok:
    sys.exit(1)
PY
then
  pass "Contracts validate against schema" "python3 (schema validation)"
else
  fail "Contracts validate against schema" "python3 (schema validation)" "validation failure"
fi

image_docs=(
  "docs/images/README.md"
  "docs/images/vm-golden-images.md"
  "docs/images/image-lifecycle.md"
  "docs/images/image-security.md"
)

for doc in "${image_docs[@]}"; do
  cmd="test -f ${doc}"
  if [[ -f "${FABRIC_REPO_ROOT}/${doc}" ]]; then
    pass "Image doc present: ${doc}" "${cmd}"
  else
    fail "Image doc present: ${doc}" "${cmd}" "missing doc"
  fi
done

if rg -n "^evidence/images/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "evidence/images is gitignored" "rg -n \"^evidence/images/\" .gitignore"
else
  fail "evidence/images is gitignored" "rg -n \"^evidence/images/\" .gitignore" "missing ignore entry"
fi

if rg -n "^artifacts/images/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "artifacts/images is gitignored" "rg -n \"^artifacts/images/\" .gitignore"
else
  fail "artifacts/images is gitignored" "rg -n \"^artifacts/images/\" .gitignore" "missing ignore entry"
fi

if rg -n "PRIVATE KEY|BEGIN .*PRIVATE|SECRET=|PASSWORD=" "${FABRIC_REPO_ROOT}/contracts/images" "${FABRIC_REPO_ROOT}/docs/images" >/dev/null 2>&1; then
  fail "No secrets in image contracts/docs" "rg -n <secret patterns> contracts/images docs/images" "secret-like content detected"
else
  pass "No secrets in image contracts/docs" "rg -n <secret patterns> contracts/images docs/images"
fi
