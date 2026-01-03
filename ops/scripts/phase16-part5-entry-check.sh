#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE16_ENTRY_CHECKLIST.md"
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
# Phase 16 Entry Checklist (Closure)

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE16_PART1_ACCEPTED.md"
  "acceptance/PHASE16_PART2_ACCEPTED.md"
  "acceptance/PHASE16_PART3_ACCEPTED.md"
  "acceptance/PHASE16_PART4_ACCEPTED.md"
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
  "docs/ai/governance.md"
  "docs/ai/risk-ledger.md"
  "docs/ai/stop-rules.md"
  "evidence/ai/risk-ledger/README.md"
  "ops/scripts/test-ai/test-no-exec.sh"
  "ops/scripts/test-ai/test-no-external-provider.sh"
  "ops/scripts/test-ai/test-routing-locked.sh"
  "ops/scripts/test-ai/test-mcp-readonly.sh"
  "ops/scripts/test-ai/test-ci-safety.sh"
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

if rg -n "test-no-exec.sh" "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh" >/dev/null 2>&1 \
  && rg -n "test-no-external-provider.sh" "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh" >/dev/null 2>&1 \
  && rg -n "test-routing-locked.sh" "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh" >/dev/null 2>&1 \
  && rg -n "test-mcp-readonly.sh" "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh" >/dev/null 2>&1 \
  && rg -n "test-ci-safety.sh" "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh" >/dev/null 2>&1; then
  pass "AI regression tests wired in validate.sh" "rg -n test-ai fabric-ci/scripts/validate.sh"
else
  fail "AI regression tests wired in validate.sh" "rg -n test-ai fabric-ci/scripts/validate.sh" "missing test wiring"
fi

make_targets=(
  "phase16.part5.entry.check"
  "phase16.part5.accept"
)

for target in "${make_targets[@]}"; do
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile"
  else
    fail "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile" "missing target"
  fi
done

if rg -n "TODO" "${FABRIC_REPO_ROOT}/ops/ai" "${FABRIC_REPO_ROOT}/contracts/ai" "${FABRIC_REPO_ROOT}/docs/ai" >/dev/null 2>&1; then
  fail "AI-related code has no TODOs" "rg -n \"TODO\" ops/ai contracts/ai docs/ai" "TODOs found"
else
  pass "AI-related code has no TODOs" "rg -n \"TODO\" ops/ai contracts/ai docs/ai"
fi

run_check "Policy gates" "make -C ${FABRIC_REPO_ROOT} policy.check"
run_check "Operator docs check" "make -C ${FABRIC_REPO_ROOT} docs.operator.check"
