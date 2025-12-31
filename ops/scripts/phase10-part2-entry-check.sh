#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE10_PART2_ENTRY_CHECKLIST.md"
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
# Phase 10 Part 2 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

if [[ -f "${FABRIC_REPO_ROOT}/acceptance/PHASE10_PART1_ACCEPTED.md" ]]; then
  pass "Phase 10 Part 1 accepted marker present" "test -f acceptance/PHASE10_PART1_ACCEPTED.md"
else
  fail "Phase 10 Part 1 accepted marker present" "test -f acceptance/PHASE10_PART1_ACCEPTED.md" "missing marker"
fi

if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
  fail "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md" "OPEN items found"
else
  pass "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md"
fi

if rg -n "ADR-0028" "${FABRIC_REPO_ROOT}/DECISIONS.md" >/dev/null 2>&1; then
  pass "ADR-0028 present" "rg -n \"ADR-0028\" DECISIONS.md"
else
  fail "ADR-0028 present" "rg -n \"ADR-0028\" DECISIONS.md" "missing ADR"
fi

if rg -n "^docs\.operator\.check:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: docs.operator.check" "rg -n \"^docs\\.operator\\.check:\" Makefile"
else
  fail "Makefile target present: docs.operator.check" "rg -n \"^docs\\.operator\\.check:\" Makefile" "missing target"
fi

scripts=(
  "ops/tenants/execute/execute-policy.yml"
  "ops/tenants/execute/validate-execute-policy.sh"
  "ops/tenants/execute/plan.sh"
  "ops/tenants/execute/apply.sh"
  "ops/tenants/execute/change-window.sh"
  "ops/tenants/execute/signer.sh"
  "ops/tenants/execute/doctor.sh"
  "ops/tenants/creds/issue.sh"
  "ops/tenants/creds/rotate.sh"
  "ops/tenants/creds/revoke.sh"
  "ops/tenants/creds/inspect.sh"
  "ops/tenants/creds/format.md"
  "ops/tenants/dr/testcases.yml"
  "ops/tenants/dr/validate-dr.sh"
  "ops/tenants/dr/run.sh"
)

for path in "${scripts[@]}"; do
  cmd="test -f ${path}"
  if [[ -f "${FABRIC_REPO_ROOT}/${path}" ]]; then
    pass "Tenant Part 2 artifact present: ${path}" "${cmd}"
  else
    fail "Tenant Part 2 artifact present: ${path}" "${cmd}" "missing file"
  fi
done

policy_cmd="bash ${FABRIC_REPO_ROOT}/ops/tenants/execute/validate-execute-policy.sh"
if ${policy_cmd} >/dev/null 2>&1; then
  pass "Tenant execute policy validates" "${policy_cmd}"
else
  fail "Tenant execute policy validates" "${policy_cmd}" "policy validation failed"
fi

targets=(
  "tenants.execute.policy.check"
  "tenants.plan"
  "tenants.apply"
  "tenants.creds.issue"
  "tenants.dr.validate"
  "tenants.dr.run"
  "phase10.part2.entry.check"
  "phase10.part2.accept"
)

for target in "${targets[@]}"; do
  cmd="rg -n \"^${target//./\\.}:\" Makefile"
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "${cmd}"
  else
    fail "Makefile target present: ${target}" "${cmd}" "missing target"
  fi
done
