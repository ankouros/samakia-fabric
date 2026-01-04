#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

out_file="${FABRIC_REPO_ROOT}/acceptance/GO_LIVE_ENTRY_CHECKLIST.md"
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
# Go-Live Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE17_STEP7_ACCEPTED.md"
  "acceptance/PHASE16_ACCEPTED.md"
  "acceptance/PHASE13_ACCEPTED.md"
  "acceptance/MILESTONE_PHASE1_12_ACCEPTED.md"
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
  "docs/operator/PRODUCTION_PLAYBOOK.md"
  "docs/operator/cookbook.md"
  "docs/operator/README.md"
  "docs/operator/evidence-and-artifacts.md"
  "acceptance/GO_LIVE_ENTRY_CHECKLIST.md"
  "ops/evidence/rebuild-index.sh"
  "ops/evidence/validate-index.sh"
  "ops/scripts/platform-regression.sh"
  "ops/scripts/platform-doctor.sh"
  "ops/scripts/test-platform/test-acceptance-markers.sh"
  "ops/scripts/test-platform/test-policy-gates.sh"
  "ops/scripts/test-platform/test-no-exec-expansion.sh"
  "ops/scripts/test-platform/test-go-live-invariants.sh"
  "ops/policy/policy-go-live.sh"
  "ROADMAP.md"
  "CHANGELOG.md"
  "REVIEW.md"
  "OPERATIONS.md"
  "README.md"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "policy-go-live.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Go-live policy wired" "rg -n policy-go-live.sh ops/policy/policy.sh"
else
  fail "Go-live policy wired" "rg -n policy-go-live.sh ops/policy/policy.sh" "missing policy wiring"
fi

make_targets=(
  "platform.doctor"
  "platform.regression"
  "go-live.entry.check"
  "go-live.accept"
)

for target in "${make_targets[@]}"; do
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile"
  else
    fail "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile" "missing target"
  fi
done

run_check "Operator docs check" "make -C ${FABRIC_REPO_ROOT} docs.operator.check"
run_check "Evidence index validation" "bash ${FABRIC_REPO_ROOT}/ops/evidence/validate-index.sh"
run_check "Platform regression" "make -C ${FABRIC_REPO_ROOT} platform.regression"
run_check "Production playbook linked" "rg -n 'PRODUCTION_PLAYBOOK' ${FABRIC_REPO_ROOT}/docs/operator/cookbook.md"
run_check "Operator index linked" "rg -n 'PRODUCTION_PLAYBOOK' ${FABRIC_REPO_ROOT}/docs/operator/README.md"
run_check "README production section" "rg -n 'Production' ${FABRIC_REPO_ROOT}/README.md"
