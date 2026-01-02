#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE13_PART1_ENTRY_CHECKLIST.md"
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
# Phase 13 Part 1 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE13_ENTRY_CHECKLIST.md"
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
  "contracts/exposure/exposure-policy.schema.json"
  "contracts/exposure/exposure-policy.yml"
  "ops/exposure/policy/load.sh"
  "ops/exposure/policy/validate.sh"
  "ops/exposure/policy/evaluate.sh"
  "ops/exposure/policy/explain.sh"
  "ops/exposure/plan/plan.sh"
  "ops/exposure/plan/render.sh"
  "ops/exposure/plan/diff.sh"
  "ops/exposure/plan/redact.sh"
  "ops/exposure/evidence/generate.sh"
  "ops/exposure/evidence/manifest.sh"
  "ops/exposure/evidence/sign.sh"
  "docs/operator/exposure.md"
  "docs/exposure/semantics.md"
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

if rg -n "^exposure\.policy\.check:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: exposure.policy.check" "rg -n '^exposure\\.policy\\.check:' Makefile"
else
  fail "Makefile target present: exposure.policy.check" "rg -n '^exposure\\.policy\\.check:' Makefile" "missing target"
fi

if rg -n "^exposure\.plan:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: exposure.plan" "rg -n '^exposure\\.plan:' Makefile"
else
  fail "Makefile target present: exposure.plan" "rg -n '^exposure\\.plan:' Makefile" "missing target"
fi

if rg -n "^exposure\.plan\.explain:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: exposure.plan.explain" "rg -n '^exposure\\.plan\\.explain:' Makefile"
else
  fail "Makefile target present: exposure.plan.explain" "rg -n '^exposure\\.plan\\.explain:' Makefile" "missing target"
fi

if rg -n "^phase13\.part1\.entry\.check:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase13.part1.entry.check" "rg -n '^phase13\\.part1\\.entry\\.check:' Makefile"
else
  fail "Makefile target present: phase13.part1.entry.check" "rg -n '^phase13\\.part1\\.entry\\.check:' Makefile" "missing target"
fi

if rg -n "^phase13\.part1\.accept:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase13.part1.accept" "rg -n '^phase13\\.part1\\.accept:' Makefile"
else
  fail "Makefile target present: phase13.part1.accept" "rg -n '^phase13\\.part1\\.accept:' Makefile" "missing target"
fi

run_check "Policy check" "make -C ${FABRIC_REPO_ROOT} policy.check"
run_check "Bindings validate" "make -C ${FABRIC_REPO_ROOT} bindings.validate TENANT=all"
run_check "Bindings render" "make -C ${FABRIC_REPO_ROOT} bindings.render TENANT=all"
run_check "Tenants validate" "make -C ${FABRIC_REPO_ROOT} tenants.validate"
