#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE12_PART4_ENTRY_CHECKLIST.md"
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
# Phase 12 Part 4 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE12_PART1_ACCEPTED.md"
  "acceptance/PHASE12_PART2_ACCEPTED.md"
  "acceptance/PHASE12_PART3_ACCEPTED.md"
  "acceptance/PHASE11_HARDENING_ACCEPTED.md"
)

for marker in "${markers[@]}"; do
  cmd="test -f ${marker}"
  if [[ -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
    pass "Marker present: ${marker}" "${cmd}"
  else
    fail "Marker present: ${marker}" "${cmd}" "missing marker"
  fi
done

if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
  fail "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md" "OPEN items found"
else
  pass "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md"
fi

files=(
  "contracts/proposals/proposal.schema.json"
  "examples/proposals/add-postgres-binding.yml"
  "examples/proposals/increase-cache-capacity.yml"
  "ops/proposals/submit.sh"
  "ops/proposals/validate.sh"
  "ops/proposals/diff.sh"
  "ops/proposals/impact.sh"
  "ops/proposals/review.sh"
  "ops/proposals/approve.sh"
  "ops/proposals/reject.sh"
  "ops/proposals/decision.sh"
  "ops/proposals/apply.sh"
  "ops/proposals/redact.sh"
  "ops/policy/policy-proposals.sh"
  "docs/operator/cookbook.md"
  "docs/consumers/onboarding.md"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "policy-proposals\\.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gate wired" "rg -n \"policy-proposals\\.sh\" ops/policy/policy.sh"
else
  fail "Policy gate wired" "rg -n \"policy-proposals\\.sh\" ops/policy/policy.sh" "policy gate not wired"
fi

make_targets=(
  "proposals.submit"
  "proposals.validate"
  "proposals.review"
  "proposals.approve"
  "proposals.reject"
  "proposals.apply"
  "phase12.part4.entry.check"
  "phase12.part4.accept"
)

for target in "${make_targets[@]}"; do
  cmd="rg -n '^${target//./\\.}:' Makefile"
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "${cmd}"
  else
    fail "Makefile target present: ${target}" "${cmd}" "missing target"
  fi
done

if rg -n "proposals\\.validate" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes proposal validation" "rg -n \"proposals\\.validate\" docs/operator/cookbook.md"
else
  fail "Cookbook includes proposal validation" "rg -n \"proposals\\.validate\" docs/operator/cookbook.md" "missing task"
fi

if rg -n "proposals\\.review" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes proposal review" "rg -n \"proposals\\.review\" docs/operator/cookbook.md"
else
  fail "Cookbook includes proposal review" "rg -n \"proposals\\.review\" docs/operator/cookbook.md" "missing task"
fi

if rg -n "proposals/inbox/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "Proposal inbox gitignored" "rg -n \"proposals/inbox/\" .gitignore"
else
  fail "Proposal inbox gitignored" "rg -n \"proposals/inbox/\" .gitignore" "missing gitignore rule"
fi
