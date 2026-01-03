#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE6_ENTRY_CHECKLIST.md"

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
# Phase 6 Entry Checklist

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

if rg -n "ADR-0023" "${FABRIC_REPO_ROOT}/DECISIONS.md" >/dev/null 2>&1; then
  pass "ADR-0023 present" "rg -n \"ADR-0023\" DECISIONS.md"
else
  fail "ADR-0023 present" "rg -n \"ADR-0023\" DECISIONS.md" "missing ADR"
fi

schema="${FABRIC_REPO_ROOT}/contracts/consumers/_schema/consumer-contract.schema.json"
if [[ -f "${schema}" ]]; then
  pass "Consumer contract schema present" "test -f contracts/consumers/_schema/consumer-contract.schema.json"
else
  fail "Consumer contract schema present" "test -f contracts/consumers/_schema/consumer-contract.schema.json" "missing schema"
fi

contracts=(
  "contracts/consumers/kubernetes/ready.yml"
  "contracts/consumers/kubernetes/enabled.yml"
  "contracts/consumers/database/ready.yml"
  "contracts/consumers/database/enabled.yml"
  "contracts/consumers/message-queue/ready.yml"
  "contracts/consumers/message-queue/enabled.yml"
  "contracts/consumers/cache/ready.yml"
  "contracts/consumers/cache/enabled.yml"
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

schema_path = root / "contracts/consumers/_schema/consumer-contract.schema.json"
contracts = [
    root / "contracts/consumers/kubernetes/ready.yml",
    root / "contracts/consumers/kubernetes/enabled.yml",
    root / "contracts/consumers/database/ready.yml",
    root / "contracts/consumers/database/enabled.yml",
    root / "contracts/consumers/message-queue/ready.yml",
    root / "contracts/consumers/message-queue/enabled.yml",
    root / "contracts/consumers/cache/ready.yml",
    root / "contracts/consumers/cache/enabled.yml",
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
    if "minimum" in schema_obj:
        if isinstance(data, int) and data < schema_obj["minimum"]:
            err(f"{path}: value {data} below minimum {schema_obj['minimum']}")
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

if rg -n "PRIVATE KEY|BEGIN .*PRIVATE|SECRET=|PASSWORD=" "${FABRIC_REPO_ROOT}/contracts" "${FABRIC_REPO_ROOT}/docs/consumers" >/dev/null 2>&1; then
  fail "No secrets in contracts or docs" "rg -n <secret patterns> contracts docs/consumers" "secret-like content detected"
else
  pass "No secrets in contracts or docs" "rg -n <secret patterns> contracts docs/consumers"
fi

if rg -n "contracts/_local/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "Local contract artifacts ignored" "rg -n \"contracts/_local/\" .gitignore"
else
  fail "Local contract artifacts ignored" "rg -n \"contracts/_local/\" .gitignore" "missing ignore entry"
fi

consumer_docs=(
  "docs/consumers/README.md"
  "docs/consumers/onboarding.md"
  "docs/consumers/kubernetes.md"
  "docs/consumers/database.md"
  "docs/consumers/message-queue.md"
  "docs/consumers/cache.md"
  "docs/consumers/disaster-recovery.md"
  "docs/consumers/slo-failure-semantics.md"
)

for doc in "${consumer_docs[@]}"; do
  cmd="test -f ${doc}"
  if [[ -f "${FABRIC_REPO_ROOT}/${doc}" ]]; then
    pass "Consumer doc present: ${doc}" "${cmd}"
  else
    fail "Consumer doc present: ${doc}" "${cmd}" "missing doc"
  fi
done

if make -C "${FABRIC_REPO_ROOT}" policy.check >/dev/null; then
  pass "Policy gates pass" "make policy.check"
else
  fail "Policy gates pass" "make policy.check" "policy.check failed"
fi
