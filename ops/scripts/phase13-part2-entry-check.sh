#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE13_PART2_ENTRY_CHECKLIST.md"
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
# Phase 13 Part 2 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE13_ENTRY_CHECKLIST.md"
  "acceptance/PHASE13_PART1_ACCEPTED.md"
  "acceptance/PHASE12_ACCEPTED.md"
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
  "contracts/exposure/approval.schema.json"
  "contracts/exposure/rollback.schema.json"
  "ops/exposure/approve/approve.sh"
  "ops/exposure/approve/reject.sh"
  "ops/exposure/approve/validate-approval.sh"
  "ops/exposure/apply/apply.sh"
  "ops/exposure/apply/validate-apply.sh"
  "ops/exposure/apply/write-artifacts.sh"
  "ops/exposure/apply/evidence.sh"
  "ops/exposure/apply/redact.sh"
  "ops/exposure/verify/verify.sh"
  "ops/exposure/verify/postcheck.sh"
  "ops/exposure/verify/drift-snapshot.sh"
  "ops/exposure/verify/evidence.sh"
  "ops/exposure/rollback/rollback.sh"
  "ops/exposure/rollback/validate-rollback.sh"
  "ops/exposure/rollback/evidence.sh"
  "docs/operator/exposure.md"
  "docs/exposure/semantics.md"
  "docs/exposure/rollback.md"
  "docs/exposure/change-window-and-signing.md"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "policy-exposure.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gates wired: policy-exposure.sh" "rg -n policy-exposure.sh ops/policy/policy.sh"
else
  fail "Policy gates wired: policy-exposure.sh" "rg -n policy-exposure.sh ops/policy/policy.sh" "policy gate missing"
fi

make_targets=(
  "exposure.approve"
  "exposure.apply"
  "exposure.verify"
  "exposure.rollback"
  "phase13.part2.entry.check"
  "phase13.part2.accept"
  "phase13.accept"
)

for target in "${make_targets[@]}"; do
  if rg -n "^${target//./\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile"
  else
    fail "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile" "missing target"
  fi
done

if rg -n "EXPOSE_EXECUTE" "${FABRIC_REPO_ROOT}/ops/exposure/apply/apply.sh" >/dev/null 2>&1; then
  pass "Apply execute guard present" "rg -n EXPOSE_EXECUTE ops/exposure/apply/apply.sh"
else
  fail "Apply execute guard present" "rg -n EXPOSE_EXECUTE ops/exposure/apply/apply.sh" "missing guard"
fi

if rg -n "ROLLBACK_EXECUTE" "${FABRIC_REPO_ROOT}/ops/exposure/rollback/rollback.sh" >/dev/null 2>&1; then
  pass "Rollback execute guard present" "rg -n ROLLBACK_EXECUTE ops/exposure/rollback/rollback.sh"
else
  fail "Rollback execute guard present" "rg -n ROLLBACK_EXECUTE ops/exposure/rollback/rollback.sh" "missing guard"
fi

if rg -n "VERIFY_LIVE" "${FABRIC_REPO_ROOT}/ops/exposure/verify/verify.sh" >/dev/null 2>&1; then
  pass "Verify live guard present" "rg -n VERIFY_LIVE ops/exposure/verify/verify.sh"
else
  fail "Verify live guard present" "rg -n VERIFY_LIVE ops/exposure/verify/verify.sh" "missing guard"
fi

if rg -n "^evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "evidence/ is gitignored" "rg -n '^evidence/' .gitignore"
else
  fail "evidence/ is gitignored" "rg -n '^evidence/' .gitignore" "missing evidence ignore"
fi

if rg -n "^artifacts/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "artifacts/ is gitignored" "rg -n '^artifacts/' .gitignore"
else
  fail "artifacts/ is gitignored" "rg -n '^artifacts/' .gitignore" "missing artifacts ignore"
fi

run_check "Policy check" "make -C ${FABRIC_REPO_ROOT} policy.check"
run_check "Docs operator check" "make -C ${FABRIC_REPO_ROOT} docs.operator.check"
run_check "Bindings validate" "make -C ${FABRIC_REPO_ROOT} bindings.validate TENANT=all"
run_check "Bindings render" "make -C ${FABRIC_REPO_ROOT} bindings.render TENANT=all"
run_check "Bindings secrets inspect" "make -C ${FABRIC_REPO_ROOT} bindings.secrets.inspect TENANT=all"
run_check "Bindings verify offline" "make -C ${FABRIC_REPO_ROOT} bindings.verify.offline TENANT=all"
run_check "Drift summary" "make -C ${FABRIC_REPO_ROOT} drift.summary TENANT=all"
