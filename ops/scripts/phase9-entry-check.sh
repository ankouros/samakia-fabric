#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE9_ENTRY_CHECKLIST.md"
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
# Phase 9 Entry Checklist

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
  "acceptance/PHASE7_ACCEPTED.md"
  "acceptance/PHASE8_PART1_ACCEPTED.md"
  "acceptance/PHASE8_PART1_1_ACCEPTED.md"
  "acceptance/PHASE8_PART1_2_ACCEPTED.md"
  "acceptance/PHASE8_PART2_ACCEPTED.md"
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

if rg -n "ADR-0026" "${FABRIC_REPO_ROOT}/DECISIONS.md" >/dev/null 2>&1; then
  pass "ADR-0026 present" "rg -n \"ADR-0026\" DECISIONS.md"
else
  fail "ADR-0026 present" "rg -n \"ADR-0026\" DECISIONS.md" "missing ADR"
fi

operator_docs=(
  "docs/operator/README.md"
  "docs/operator/cookbook.md"
  "docs/operator/safety-model.md"
  "docs/operator/glossary.md"
  "docs/operator/evidence-and-artifacts.md"
)

for doc in "${operator_docs[@]}"; do
  cmd="test -f ${doc}"
  if [[ -f "${FABRIC_REPO_ROOT}/${doc}" ]]; then
    pass "Operator doc present: ${doc}" "${cmd}"
  else
    fail "Operator doc present: ${doc}" "${cmd}" "missing doc"
  fi
done

consumer_docs=(
  "docs/consumers/catalog.md"
  "docs/consumers/quickstart.md"
)

for doc in "${consumer_docs[@]}"; do
  cmd="test -f ${doc}"
  if [[ -f "${FABRIC_REPO_ROOT}/${doc}" ]]; then
    pass "Consumer doc present: ${doc}" "${cmd}"
  else
    fail "Consumer doc present: ${doc}" "${cmd}" "missing doc"
  fi
done

ops_docs=(
  "ops/docs/operator-inventory.sh"
  "ops/docs/cookbook-lint.sh"
  "ops/docs/docs-antidrift-check.sh"
  "ops/docs/waivers.yml"
)

for doc in "${ops_docs[@]}"; do
  cmd="test -f ${doc}"
  if [[ -f "${FABRIC_REPO_ROOT}/${doc}" ]]; then
    pass "Anti-drift tooling present: ${doc}" "${cmd}"
  else
    fail "Anti-drift tooling present: ${doc}" "${cmd}" "missing tooling"
  fi
done

if rg -n "^docs\.operator\.check:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: docs.operator.check" "rg -n \"^docs\\.operator\\.check:\" Makefile"
else
  fail "Makefile target present: docs.operator.check" "rg -n \"^docs\\.operator\\.check:\" Makefile" "missing target"
fi

if rg -n "docs\.operator\.check" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1; then
  pass "PR validation runs docs.operator.check" "rg -n \"docs\\.operator\\.check\" .github/workflows/pr-validate.yml"
else
  fail "PR validation runs docs.operator.check" "rg -n \"docs\\.operator\\.check\" .github/workflows/pr-validate.yml" "missing workflow step"
fi

if rg -n "PRIVATE KEY|BEGIN .*PRIVATE|SECRET=|PASSWORD=" "${FABRIC_REPO_ROOT}/docs/operator" "${FABRIC_REPO_ROOT}/docs/consumers" >/dev/null 2>&1; then
  fail "No secrets in operator/consumer docs" "rg -n <secret patterns> docs/operator docs/consumers" "secret-like content detected"
else
  pass "No secrets in operator/consumer docs" "rg -n <secret patterns> docs/operator docs/consumers"
fi
