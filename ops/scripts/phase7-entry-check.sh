#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE7_ENTRY_CHECKLIST.md"

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
# Phase 7 Entry Checklist

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

if rg -n "ADR-0024" "${FABRIC_REPO_ROOT}/DECISIONS.md" >/dev/null 2>&1; then
  pass "ADR-0024 present" "rg -n \"ADR-0024\" DECISIONS.md"
else
  fail "ADR-0024 present" "rg -n \"ADR-0024\" DECISIONS.md" "missing ADR"
fi

policy_file="${FABRIC_REPO_ROOT}/AI_OPERATIONS_POLICY.md"
if [[ -f "${policy_file}" ]]; then
  pass "AI operations policy present" "test -f AI_OPERATIONS_POLICY.md"
else
  fail "AI operations policy present" "test -f AI_OPERATIONS_POLICY.md" "missing policy"
fi

required_files=(
  "ops/ai/plan-review/plan-review.sh"
  "ops/ai/remediate/remediate.sh"
  "ops/policy/policy-ai-ops.sh"
  "ops/scripts/safe-index.yml"
  "ops/scripts/safe-run.sh"
  "ops/scripts/ai-runbook-check.sh"
  "ops/scripts/ai-safe-index-check.sh"
)

for path in "${required_files[@]}"; do
  cmd="test -f ${path}"
  if [[ -f "${FABRIC_REPO_ROOT}/${path}" ]]; then
    pass "Required file present: ${path}" "${cmd}"
  else
    fail "Required file present: ${path}" "${cmd}" "missing file"
  fi
done

runbooks=(
  "ops/runbooks/ai/format.md"
  "ops/runbooks/ai/incident-triage.md"
  "ops/runbooks/ai/drift-triage.md"
  "ops/runbooks/ai/consumer-readiness-triage.md"
  "ops/runbooks/ai/observability-triage.md"
)

for doc in "${runbooks[@]}"; do
  cmd="test -f ${doc}"
  if [[ -f "${FABRIC_REPO_ROOT}/${doc}" ]]; then
    pass "AI runbook present: ${doc}" "${cmd}"
  else
    fail "AI runbook present: ${doc}" "${cmd}" "missing runbook"
  fi
done

if rg -n "^evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "evidence/ is gitignored" "rg -n \"^evidence/\" .gitignore"
else
  fail "evidence/ is gitignored" "rg -n \"^evidence/\" .gitignore" "missing ignore entry"
fi

if rg -n "^artifacts/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "artifacts/ is gitignored" "rg -n \"^artifacts/\" .gitignore"
else
  fail "artifacts/ is gitignored" "rg -n \"^artifacts/\" .gitignore" "missing ignore entry"
fi

if rg -n "AI_REMEDIATE=1|GAMEDAY_EXECUTE=1|SAFE_RUN_EXECUTE=1" "${FABRIC_REPO_ROOT}/.github/workflows" >/dev/null 2>&1; then
  fail "CI workflows do not enable execute flags" "rg -n <execute flags> .github/workflows" "execute flag detected"
else
  pass "CI workflows do not enable execute flags" "rg -n <execute flags> .github/workflows"
fi

if rg -n "policy-ai-ops.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "policy-ai-ops wired into policy.check" "rg -n policy-ai-ops.sh ops/policy/policy.sh"
else
  fail "policy-ai-ops wired into policy.check" "rg -n policy-ai-ops.sh ops/policy/policy.sh" "missing policy hook"
fi

if make -C "${FABRIC_REPO_ROOT}" policy.check >/dev/null; then
  pass "Policy gates pass" "make policy.check"
else
  fail "Policy gates pass" "make policy.check" "policy.check failed"
fi
