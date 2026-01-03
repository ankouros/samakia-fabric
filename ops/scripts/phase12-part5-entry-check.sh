#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE12_PART5_ENTRY_CHECKLIST.md"
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
# Phase 12 Part 5 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE12_PART1_ACCEPTED.md"
  "acceptance/PHASE12_PART2_ACCEPTED.md"
  "acceptance/PHASE12_PART3_ACCEPTED.md"
  "acceptance/PHASE12_PART4_ACCEPTED.md"
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
  "docs/drift/overview.md"
  "docs/drift/taxonomy.md"
  "docs/operator/cookbook.md"
  "docs/consumers/onboarding.md"
  "ops/drift/detect.sh"
  "ops/drift/summary.sh"
  "ops/drift/classify.sh"
  "ops/drift/redact.sh"
  "ops/drift/compare/bindings.sh"
  "ops/drift/compare/capacity.sh"
  "ops/drift/compare/security.sh"
  "ops/drift/compare/availability.sh"
  "ops/policy/policy-drift.sh"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "policy-drift\\.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gate wired" "rg -n \"policy-drift\\.sh\" ops/policy/policy.sh"
else
  fail "Policy gate wired" "rg -n \"policy-drift\\.sh\" ops/policy/policy.sh" "policy gate not wired"
fi

make_targets=(
  "drift.detect"
  "drift.summary"
  "phase12.part5.entry.check"
  "phase12.part5.accept"
)

for target in "${make_targets[@]}"; do
  cmd="rg -n '^${target//./\\.}:' Makefile"
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "${cmd}"
  else
    fail "Makefile target present: ${target}" "${cmd}" "missing target"
  fi
done

if rg -n "drift\\.detect" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes drift.detect" "rg -n \"drift\\.detect\" docs/operator/cookbook.md"
else
  fail "Cookbook includes drift.detect" "rg -n \"drift\\.detect\" docs/operator/cookbook.md" "missing task"
fi

if rg -n "drift\\.summary" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes drift.summary" "rg -n \"drift\\.summary\" docs/operator/cookbook.md"
else
  fail "Cookbook includes drift.summary" "rg -n \"drift\\.summary\" docs/operator/cookbook.md" "missing task"
fi

if rg -n "phase12\\.part5\\.accept" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes Phase 12 Part 5 acceptance" "rg -n \"phase12\\.part5\\.accept\" docs/operator/cookbook.md"
else
  fail "Cookbook includes Phase 12 Part 5 acceptance" "rg -n \"phase12\\.part5\\.accept\" docs/operator/cookbook.md" "missing task"
fi

if rg -n "drift\\.detect" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1; then
  pass "CI drift detect wired" "rg -n \"drift\\.detect\" .github/workflows/pr-validate.yml"
else
  fail "CI drift detect wired" "rg -n \"drift\\.detect\" .github/workflows/pr-validate.yml" "missing step"
fi

if rg -n "^artifacts/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "Artifacts gitignored" "rg -n \"^artifacts/\" .gitignore"
else
  fail "Artifacts gitignored" "rg -n \"^artifacts/\" .gitignore" "missing gitignore rule"
fi
