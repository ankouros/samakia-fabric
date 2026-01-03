#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE10_ENTRY_CHECKLIST.md"
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
# Phase 10 Entry Checklist

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

if rg -n "ADR-0027" "${FABRIC_REPO_ROOT}/DECISIONS.md" >/dev/null 2>&1; then
  pass "ADR-0027 present" "rg -n \"ADR-0027\" DECISIONS.md"
else
  fail "ADR-0027 present" "rg -n \"ADR-0027\" DECISIONS.md" "missing ADR"
fi

schemas=(
  "contracts/tenants/_schema/tenant.schema.json"
  "contracts/tenants/_schema/policies.schema.json"
  "contracts/tenants/_schema/quotas.schema.json"
  "contracts/tenants/_schema/endpoints.schema.json"
  "contracts/tenants/_schema/networks.schema.json"
  "contracts/tenants/_schema/consumer-binding.schema.json"
)

for schema in "${schemas[@]}"; do
  cmd="test -f ${schema}"
  if [[ -f "${FABRIC_REPO_ROOT}/${schema}" ]]; then
    pass "Schema present: ${schema}" "${cmd}"
  else
    fail "Schema present: ${schema}" "${cmd}" "missing schema"
  fi
done

templates=(
  "contracts/tenants/_templates/tenant.yml"
  "contracts/tenants/_templates/policies.yml"
  "contracts/tenants/_templates/quotas.yml"
  "contracts/tenants/_templates/endpoints.yml"
  "contracts/tenants/_templates/networks.yml"
  "contracts/tenants/_templates/consumers/database/ready.yml"
  "contracts/tenants/_templates/consumers/message-queue/ready.yml"
  "contracts/tenants/_templates/consumers/cache/ready.yml"
  "contracts/tenants/_templates/consumers/vector/ready.yml"
  "contracts/tenants/_templates/consumers/kubernetes/ready.yml"
)

for template in "${templates[@]}"; do
  cmd="test -f ${template}"
  if [[ -f "${FABRIC_REPO_ROOT}/${template}" ]]; then
    pass "Template present: ${template}" "${cmd}"
  else
    fail "Template present: ${template}" "${cmd}" "missing template"
  fi
done

examples=(
  "contracts/tenants/examples/samakia-internal-tools"
  "contracts/tenants/examples/project-birds"
)

for example in "${examples[@]}"; do
  cmd="test -f ${example}/tenant.yml"
  if [[ -f "${FABRIC_REPO_ROOT}/${example}/tenant.yml" ]]; then
    pass "Example tenant present: ${example}" "${cmd}"
  else
    fail "Example tenant present: ${example}" "${cmd}" "missing example"
  fi
done

if rg -n "^tenants\.validate:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: tenants.validate" "rg -n \"^tenants\\.validate:\" Makefile"
else
  fail "Makefile target present: tenants.validate" "rg -n \"^tenants\\.validate:\" Makefile" "missing target"
fi

if rg -n "^phase10\.entry\.check:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase10.entry.check" "rg -n \"^phase10\\.entry\\.check:\" Makefile"
else
  fail "Makefile target present: phase10.entry.check" "rg -n \"^phase10\\.entry\\.check:\" Makefile" "missing target"
fi

if rg -n "tenants\.validate" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1; then
  pass "PR validation runs tenants.validate" "rg -n \"tenants\\.validate\" .github/workflows/pr-validate.yml"
else
  fail "PR validation runs tenants.validate" "rg -n \"tenants\\.validate\" .github/workflows/pr-validate.yml" "missing workflow step"
fi

tenant_docs=(
  "docs/tenants/README.md"
  "docs/tenants/onboarding.md"
  "docs/tenants/isolation-model.md"
  "docs/tenants/policies-and-quotas.md"
  "docs/tenants/credentials-and-endpoints.md"
  "docs/tenants/consumer-bindings.md"
)

for doc in "${tenant_docs[@]}"; do
  cmd="test -f ${doc}"
  if [[ -f "${FABRIC_REPO_ROOT}/${doc}" ]]; then
    pass "Tenant doc present: ${doc}" "${cmd}"
  else
    fail "Tenant doc present: ${doc}" "${cmd}" "missing doc"
  fi
done

if [[ -f "${FABRIC_REPO_ROOT}/acceptance/PHASE10_ACCEPTANCE_PLAN.md" ]]; then
  pass "Acceptance plan present: acceptance/PHASE10_ACCEPTANCE_PLAN.md" "test -f acceptance/PHASE10_ACCEPTANCE_PLAN.md"
else
  fail "Acceptance plan present: acceptance/PHASE10_ACCEPTANCE_PLAN.md" "test -f acceptance/PHASE10_ACCEPTANCE_PLAN.md" "missing plan"
fi
