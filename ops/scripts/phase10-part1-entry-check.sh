#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE10_PART1_ENTRY_CHECKLIST.md"
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
# Phase 10 Part 1 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

if [[ -f "${FABRIC_REPO_ROOT}/acceptance/PHASE9_ACCEPTED.md" ]]; then
  pass "Phase 9 accepted marker present" "test -f acceptance/PHASE9_ACCEPTED.md"
else
  fail "Phase 9 accepted marker present" "test -f acceptance/PHASE9_ACCEPTED.md" "missing marker"
fi

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

if rg -n "^docs\\.operator\\.check:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: docs.operator.check" "rg -n \"^docs\\.operator\\.check:\" Makefile"
else
  fail "Makefile target present: docs.operator.check" "rg -n \"^docs\\.operator\\.check:\" Makefile" "missing target"
fi

targets=(
  "tenants.validate"
  "tenants.evidence"
  "tenants.doctor"
  "phase10.part1.entry.check"
  "phase10.part1.accept"
)

for target in "${targets[@]}"; do
  cmd="rg -n \"^${target//./\\.}:\" Makefile"
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "${cmd}"
  else
    fail "Makefile target present: ${target}" "${cmd}" "missing target"
  fi
done

tenant_paths=(
  "contracts/tenants/_schema/tenant.schema.json"
  "contracts/tenants/_schema/policies.schema.json"
  "contracts/tenants/_schema/quotas.schema.json"
  "contracts/tenants/_schema/endpoints.schema.json"
  "contracts/tenants/_schema/networks.schema.json"
  "contracts/tenants/_schema/consumer-binding.schema.json"
  "contracts/tenants/_schema/dr-testcases.yml"
  "contracts/tenants/_templates/tenant.yml"
  "contracts/tenants/_templates/policies.yml"
  "contracts/tenants/_templates/quotas.yml"
  "contracts/tenants/_templates/endpoints.yml"
  "contracts/tenants/_templates/networks.yml"
  "contracts/tenants/examples/samakia-internal-tools/tenant.yml"
  "contracts/tenants/examples/project-birds/tenant.yml"
)

for path in "${tenant_paths[@]}"; do
  cmd="test -f ${path}"
  if [[ -f "${FABRIC_REPO_ROOT}/${path}" ]]; then
    pass "Tenant artifact present: ${path}" "${cmd}"
  else
    fail "Tenant artifact present: ${path}" "${cmd}" "missing file"
  fi
done
