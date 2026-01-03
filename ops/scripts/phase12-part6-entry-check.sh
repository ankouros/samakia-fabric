#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE12_PART6_ENTRY_CHECKLIST.md"
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
# Phase 12 Part 6 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE12_PART1_ACCEPTED.md"
  "acceptance/PHASE12_PART2_ACCEPTED.md"
  "acceptance/PHASE12_PART3_ACCEPTED.md"
  "acceptance/PHASE12_PART4_ACCEPTED.md"
  "acceptance/PHASE12_PART5_ACCEPTED.md"
  "acceptance/PHASE11_HARDENING_ACCEPTED.md"
)

for marker in "${markers[@]}"; do
  cmd="test -f ${marker}"
  if [[ -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
    pass "Marker present: ${marker}" "${cmd}"
  else
    fail "Marker present: ${marker}" "${cmd}" "missing marker"
  fi
done

if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
  fail "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md" "OPEN items found"
else
  pass "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md"
fi

files=(
  "ops/release/phase12/phase12-readiness-packet.sh"
  "ops/release/phase12/phase12-readiness-manifest.sh"
  "ops/release/phase12/phase12-readiness-redact.sh"
  "ops/scripts/test-phase12/test-phase12-targets.sh"
  "ops/scripts/test-phase12/test-phase12-guards.sh"
  "ops/scripts/test-phase12/test-phase12-docs-generated.sh"
  "ops/scripts/test-phase12/test-phase12-readiness-packet.sh"
  "docs/operator/phase12-exposure.md"
  "docs/operator/cookbook.md"
  "docs/operator/README.md"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "test-phase12" "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh" >/dev/null 2>&1; then
  pass "Phase 12 tests wired" "rg -n \"test-phase12\" fabric-ci/scripts/validate.sh"
else
  fail "Phase 12 tests wired" "rg -n \"test-phase12\" fabric-ci/scripts/validate.sh" "missing wiring"
fi

policy_scripts=(
  "policy-bindings-verify.sh"
  "policy-proposals.sh"
  "policy-drift.sh"
  "policy-secrets-materialization.sh"
  "policy-secrets-rotation.sh"
)

for policy in "${policy_scripts[@]}"; do
  if rg -n "${policy}" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
    pass "Policy gate wired: ${policy}" "rg -n \"${policy}\" ops/policy/policy.sh"
  else
    fail "Policy gate wired: ${policy}" "rg -n \"${policy}\" ops/policy/policy.sh" "policy gate not wired"
  fi
done

make_targets=(
  "phase12.readiness.packet"
  "phase12.part6.entry.check"
  "phase12.part6.accept"
  "phase12.accept"
  "bindings.validate"
  "bindings.render"
  "bindings.secrets.inspect"
  "bindings.verify.offline"
  "drift.summary"
)

for target in "${make_targets[@]}"; do
  cmd="rg -n '^${target//./\\.}:' Makefile"
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "${cmd}"
  else
    fail "Makefile target present: ${target}" "${cmd}" "missing target"
  fi
done

if rg -n "phase12\.accept" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes phase12.accept" "rg -n \"phase12\\.accept\" docs/operator/cookbook.md"
else
  fail "Cookbook includes phase12.accept" "rg -n \"phase12\\.accept\" docs/operator/cookbook.md" "missing task"
fi
