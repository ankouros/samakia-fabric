#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE16_PART4_ENTRY_CHECKLIST.md"
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
# Phase 16 Part 4 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE16_PART3_ACCEPTED.md"
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
  "contracts/ai/analysis.schema.json"
  "contracts/ai/analysis.yml"
  "ops/ai/analysis/analyze.sh"
  "ops/ai/analysis/assemble-context.sh"
  "ops/ai/analysis/call-ollama.sh"
  "ops/ai/analysis/evidence.sh"
  "ops/ai/analysis/redact.sh"
  "ops/ai/analysis/prompts/drift_explain.md"
  "ops/ai/analysis/prompts/slo_explain.md"
  "ops/ai/analysis/prompts/incident_summary.md"
  "ops/ai/analysis/prompts/plan_review.md"
  "ops/ai/analysis/prompts/change_impact.md"
  "ops/ai/analysis/prompts/compliance_summary.md"
  "ops/policy/policy-ai-analysis.sh"
  "docs/ai/analysis.md"
  "docs/ai/examples.md"
  "docs/operator/ai-analysis.md"
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

if rg -n "policy-ai-analysis\.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gate wired: policy-ai-analysis.sh" "rg -n policy-ai-analysis\.sh ops/policy/policy.sh"
else
  fail "Policy gate wired: policy-ai-analysis.sh" "rg -n policy-ai-analysis\.sh ops/policy/policy.sh" "policy gate missing"
fi

make_targets=(
  "ai.analyze.plan"
  "ai.analyze.run"
  "ai.analyze.compare"
  "phase16.part4.entry.check"
  "phase16.part4.accept"
)

for target in "${make_targets[@]}"; do
  if rg -n "^${target//./\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "rg -n '^${target//./\.}:' Makefile"
  else
    fail "Makefile target present: ${target}" "rg -n '^${target//./\.}:' Makefile" "missing target"
  fi
done

run_check "AI analysis policy" "bash ${FABRIC_REPO_ROOT}/ops/policy/policy-ai-analysis.sh"
run_check "Operator docs check" "make -C ${FABRIC_REPO_ROOT} docs.operator.check"
