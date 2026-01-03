#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE15_PART1_ENTRY_CHECKLIST.md"
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
# Phase 15 Part 1 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE14_PART3_ACCEPTED.md"
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
  "contracts/selfservice/proposal.schema.json"
  "contracts/selfservice/README.md"
  "examples/selfservice/example.yml"
  "ops/selfservice/submit.sh"
  "ops/selfservice/validate.sh"
  "ops/selfservice/normalize.sh"
  "ops/selfservice/diff.sh"
  "ops/selfservice/impact.sh"
  "ops/selfservice/plan.sh"
  "ops/selfservice/review.sh"
  "ops/selfservice/redact.sh"
  "ops/policy/policy-selfservice.sh"
  "docs/tenants/selfservice.md"
  "docs/operator/selfservice-review.md"
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

if rg -n "policy-selfservice\.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gates wired: policy-selfservice.sh" "rg -n policy-selfservice\\.sh ops/policy/policy.sh"
else
  fail "Policy gates wired: policy-selfservice.sh" "rg -n policy-selfservice\\.sh ops/policy/policy.sh" "policy gate missing"
fi

make_targets=(
  "selfservice.submit"
  "selfservice.validate"
  "selfservice.plan"
  "selfservice.review"
  "phase15.part1.entry.check"
  "phase15.part1.accept"
)

for target in "${make_targets[@]}"; do
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile"
  else
    fail "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile" "missing target"
  fi
done

run_check "CI wiring: selfservice.validate" "rg -n 'selfservice.validate' .github/workflows/pr-validate.yml"
run_check "Selfservice inbox gitignored" "rg -n 'selfservice/inbox/' .gitignore"
run_check "Operator targets include selfservice" "rg -n 'selfservice\\.' ops/docs/operator-targets.json"
run_check "Cookbook includes selfservice review" "rg -n 'selfservice\\.review' docs/operator/cookbook.md"

run_check "Policy check" "make -C ${FABRIC_REPO_ROOT} policy.check"
run_check "Runtime evaluate" "make -C ${FABRIC_REPO_ROOT} runtime.evaluate TENANT=all"
run_check "SLO evaluate" "make -C ${FABRIC_REPO_ROOT} slo.evaluate TENANT=all"
run_check "Drift summary" "make -C ${FABRIC_REPO_ROOT} drift.summary TENANT=all"
