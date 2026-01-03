#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE11_PART5_ENTRY_CHECKLIST.md"
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
# Phase 11 Part 5 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

marker="acceptance/PHASE11_PART4_ACCEPTED.md"
cmd="test -f ${marker}"
if [[ -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
  pass "Phase 11 Part 4 accepted" "${cmd}"
else
  fail "Phase 11 Part 4 accepted" "${cmd}" "missing Part 4 marker"
fi

if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
  fail "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md" "OPEN items found"
else
  pass "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md"
fi

files=(
  "contracts/alerting/routing.yml"
  "contracts/alerting/alerting.schema.json"
  "contracts/alerting/README.md"
  "ops/substrate/alert/validate-routing.sh"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "substrate.alert.validate" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: substrate.alert.validate" "rg -n \"substrate.alert.validate\" Makefile"
else
  fail "Makefile target present: substrate.alert.validate" "rg -n \"substrate.alert.validate\" Makefile" "missing target"
fi

if rg -n "phase11.part5.entry.check" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase11.part5.entry.check" "rg -n \"phase11.part5.entry.check\" Makefile"
else
  fail "Makefile target present: phase11.part5.entry.check" "rg -n \"phase11.part5.entry.check\" Makefile" "missing target"
fi

if rg -n "phase11.part5.routing.accept" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase11.part5.routing.accept" "rg -n \"phase11.part5.routing.accept\" Makefile"
else
  fail "Makefile target present: phase11.part5.routing.accept" "rg -n \"phase11.part5.routing.accept\" Makefile" "missing target"
fi
