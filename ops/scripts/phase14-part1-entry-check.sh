#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE14_PART1_ENTRY_CHECKLIST.md"
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
# Phase 14 Part 1 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE14_ENTRY_CHECKLIST.md"
  "acceptance/PHASE13_ACCEPTED.md"
  "acceptance/MILESTONE_PHASE1_12_ACCEPTED.md"
  "acceptance/PHASE11_HARDENING_ACCEPTED.md"
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
  "ops/runtime/evaluate.sh"
  "ops/runtime/load/signals.sh"
  "ops/runtime/load/slo.sh"
  "ops/runtime/load/observation.sh"
  "ops/runtime/classify/infra.sh"
  "ops/runtime/classify/drift.sh"
  "ops/runtime/classify/slo.sh"
  "ops/runtime/normalize/metrics.sh"
  "ops/runtime/normalize/time.sh"
  "ops/runtime/redact.sh"
  "ops/runtime/evidence.sh"
  "ops/policy/policy-runtime-eval.sh"
  "contracts/slo/slo.schema.json"
  "contracts/runtime-observation/observation.yml"
  "docs/operator/runtime-ops.md"
  "docs/runtime/signal-taxonomy.md"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "policy-runtime-eval.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gates wired: policy-runtime-eval.sh" "rg -n policy-runtime-eval.sh ops/policy/policy.sh"
else
  fail "Policy gates wired: policy-runtime-eval.sh" "rg -n policy-runtime-eval.sh ops/policy/policy.sh" "policy gate missing"
fi

make_targets=(
  "runtime.evaluate"
  "runtime.status"
  "phase14.part1.entry.check"
  "phase14.part1.accept"
)

for target in "${make_targets[@]}"; do
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile"
  else
    fail "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile" "missing target"
  fi
done

run_check "CI wiring: runtime.evaluate" "rg -n 'runtime.evaluate' .github/workflows/pr-validate.yml"
run_check "CI wiring: runtime.status" "rg -n 'runtime.status' .github/workflows/pr-validate.yml"
run_check "No remediation code paths" "! rg -n 'remediate|self-heal|auto-remediate' ops/runtime"

run_check "Policy check" "make -C ${FABRIC_REPO_ROOT} policy.check"
run_check "Docs operator check" "make -C ${FABRIC_REPO_ROOT} docs.operator.check"
run_check "Drift summary" "make -C ${FABRIC_REPO_ROOT} drift.summary TENANT=all"
