#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE17_STEP5_ENTRY_CHECKLIST.md"
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

run_check() {
  local label="$1"
  local cmd="$2"
  if bash -lc "${cmd}"; then
    pass "${label}" "${cmd}"
  else
    fail "${label}" "${cmd}" "command failed"
  fi
}

cat >"${out_file}" <<EOF_HEAD
# Phase 17 Step 5 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE12_PART2_ACCEPTED.md"
  "acceptance/PHASE12_PART3_ACCEPTED.md"
  "acceptance/PHASE13_ACCEPTED.md"
  "acceptance/PHASE17_STEP4_ACCEPTED.md"
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

files=(
  "contracts/rotation/cutover.schema.json"
  "contracts/rotation/README.md"
  "contracts/rotation/examples/cutover-nonprod.yml"
  "ops/bindings/rotate/cutover-plan.sh"
  "ops/bindings/rotate/cutover-apply.sh"
  "ops/bindings/rotate/cutover-rollback.sh"
  "ops/bindings/rotate/cutover-validate.sh"
  "ops/bindings/rotate/cutover-evidence.sh"
  "ops/bindings/rotate/redact.sh"
  "ops/policy/policy-rotation-cutover.sh"
  "docs/operator/secrets-rotation.md"
  "docs/operator/cookbook.md"
  "OPERATIONS.md"
  "ROADMAP.md"
  "CHANGELOG.md"
  "REVIEW.md"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "policy-rotation-cutover.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Cutover policy wired" "rg -n policy-rotation-cutover.sh ops/policy/policy.sh"
else
  fail "Cutover policy wired" "rg -n policy-rotation-cutover.sh ops/policy/policy.sh" "missing policy wiring"
fi

make_targets=(
  "rotation.cutover.plan"
  "rotation.cutover.apply"
  "rotation.cutover.rollback"
  "phase17.step5.entry.check"
  "phase17.step5.accept"
)

for target in "${make_targets[@]}"; do
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile"
  else
    fail "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile" "missing target"
  fi
done

run_check "Policy gates" "make -C ${FABRIC_REPO_ROOT} policy.check"
run_check "Bindings validate" "make -C ${FABRIC_REPO_ROOT} bindings.validate TENANT=all"
run_check "Bindings render" "make -C ${FABRIC_REPO_ROOT} bindings.render TENANT=all"
run_check "Bindings secrets inspect" "make -C ${FABRIC_REPO_ROOT} bindings.secrets.inspect TENANT=all"
run_check "Bindings verify (offline)" "make -C ${FABRIC_REPO_ROOT} bindings.verify.offline TENANT=all"
