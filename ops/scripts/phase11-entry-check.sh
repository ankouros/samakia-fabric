#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE11_ENTRY_CHECKLIST.md"
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
# Phase 11 Entry Checklist

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
  "acceptance/PHASE9_ACCEPTED.md"
  "acceptance/PHASE10_PART1_ACCEPTED.md"
  "acceptance/PHASE10_PART2_ACCEPTED.md"
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

if rg -n "ADR-0029" "${FABRIC_REPO_ROOT}/DECISIONS.md" >/dev/null 2>&1; then
  pass "ADR-0029 present" "rg -n \"ADR-0029\" DECISIONS.md"
else
  fail "ADR-0029 present" "rg -n \"ADR-0029\" DECISIONS.md" "missing ADR"
fi

schemas=(
  "contracts/tenants/_schema/enabled-executor.schema.json"
  "contracts/tenants/_schema/enabled-dr.schema.json"
  "contracts/tenants/_schema/enabled-resources.schema.json"
  "contracts/tenants/_schema/enabled-binding.schema.json"
)

for schema in "${schemas[@]}"; do
  cmd="test -f ${schema}"
  if [[ -f "${FABRIC_REPO_ROOT}/${schema}" ]]; then
    pass "Schema present: ${schema}" "${cmd}"
  else
    fail "Schema present: ${schema}" "${cmd}" "missing schema"
  fi
done

contracts=(
  "contracts/substrate/README.md"
  "contracts/substrate/dr-testcases.yml"
)

for contract in "${contracts[@]}"; do
  cmd="test -f ${contract}"
  if [[ -f "${FABRIC_REPO_ROOT}/${contract}" ]]; then
    pass "Substrate contract present: ${contract}" "${cmd}"
  else
    fail "Substrate contract present: ${contract}" "${cmd}" "missing contract"
  fi
done

templates=(
  "contracts/tenants/_templates/consumers/database/enabled.yml"
  "contracts/tenants/_templates/consumers/message-queue/enabled.yml"
  "contracts/tenants/_templates/consumers/cache/enabled.yml"
  "contracts/tenants/_templates/consumers/vector/enabled.yml"
)

for template in "${templates[@]}"; do
  cmd="test -f ${template}"
  if [[ -f "${FABRIC_REPO_ROOT}/${template}" ]]; then
    pass "Template present: ${template}" "${cmd}"
  else
    fail "Template present: ${template}" "${cmd}" "missing template"
  fi
done

scripts=(
  "ops/substrate/validate-dr-taxonomy.sh"
  "ops/substrate/validate-enabled-contracts.sh"
  "ops/substrate/validate.sh"
)

for script in "${scripts[@]}"; do
  cmd="test -f ${script}"
  if [[ -f "${FABRIC_REPO_ROOT}/${script}" ]]; then
    pass "Validation script present: ${script}" "${cmd}"
  else
    fail "Validation script present: ${script}" "${cmd}" "missing script"
  fi
done

if rg -n "^substrate\.contracts\.validate:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: substrate.contracts.validate" "rg -n \"^substrate\\.contracts\\.validate:\" Makefile"
else
  fail "Makefile target present: substrate.contracts.validate" "rg -n \"^substrate\\.contracts\\.validate:\" Makefile" "missing target"
fi

if rg -n "^phase11\.entry\.check:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase11.entry.check" "rg -n \"^phase11\\.entry\\.check:\" Makefile"
else
  fail "Makefile target present: phase11.entry.check" "rg -n \"^phase11\\.entry\\.check:\" Makefile" "missing target"
fi

if rg -n "substrate\.contracts\.validate" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1; then
  pass "PR validation runs substrate.contracts.validate" "rg -n \"substrate\\.contracts\\.validate\" .github/workflows/pr-validate.yml"
else
  fail "PR validation runs substrate.contracts.validate" "rg -n \"substrate\\.contracts\\.validate\" .github/workflows/pr-validate.yml" "missing workflow step"
fi

if [[ -f "${FABRIC_REPO_ROOT}/acceptance/PHASE11_ACCEPTANCE_PLAN.md" ]]; then
  pass "Acceptance plan present: acceptance/PHASE11_ACCEPTANCE_PLAN.md" "test -f acceptance/PHASE11_ACCEPTANCE_PLAN.md"
else
  fail "Acceptance plan present: acceptance/PHASE11_ACCEPTANCE_PLAN.md" "test -f acceptance/PHASE11_ACCEPTANCE_PLAN.md" "missing plan"
fi
