#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE14_PART2_ENTRY_CHECKLIST.md"
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
# Phase 14 Part 2 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE14_PART1_ACCEPTED.md"
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
  "ops/slo/ingest.sh"
  "ops/slo/evaluate.sh"
  "ops/slo/windows.sh"
  "ops/slo/error-budget.sh"
  "ops/slo/normalize.sh"
  "ops/slo/redact.sh"
  "ops/slo/evidence.sh"
  "ops/slo/alerting/rules-generate.sh"
  "ops/slo/alerting/rules-validate.sh"
  "ops/policy/policy-slo.sh"
  "contracts/slo/slo.schema.json"
  "contracts/runtime-observation/observation.yml"
  "docs/operator/slo.md"
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

if rg -n "policy-slo.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gates wired: policy-slo.sh" "rg -n policy-slo.sh ops/policy/policy.sh"
else
  fail "Policy gates wired: policy-slo.sh" "rg -n policy-slo.sh ops/policy/policy.sh" "policy gate missing"
fi

make_targets=(
  "slo.ingest.offline"
  "slo.ingest.live"
  "slo.evaluate"
  "slo.alerts.generate"
  "phase14.part2.entry.check"
  "phase14.part2.accept"
)

for target in "${make_targets[@]}"; do
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile"
  else
    fail "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile" "missing target"
  fi
done

run_check "CI wiring: slo.ingest.offline" "rg -n 'slo.ingest.offline' .github/workflows/pr-validate.yml"
run_check "CI wiring: slo.evaluate" "rg -n 'slo.evaluate' .github/workflows/pr-validate.yml"
run_check "CI wiring: slo.alerts.generate" "rg -n 'slo.alerts.generate' .github/workflows/pr-validate.yml"
run_check "No remediation or delivery enablement" "! rg -n 'alertmanager|pagerduty|opsgenie|slack|webhook|remediate|self-heal' ops/slo"

run_check "Policy check" "make -C ${FABRIC_REPO_ROOT} policy.check"
run_check "Docs operator check" "make -C ${FABRIC_REPO_ROOT} docs.operator.check"
run_check "Runtime evaluate" "make -C ${FABRIC_REPO_ROOT} runtime.evaluate TENANT=all"
