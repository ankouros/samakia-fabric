#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE11_HARDENING_ENTRY_CHECKLIST.md"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

section() {
  echo >>"${out_file}"
  echo "## $1" >>"${out_file}"
}

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
# Phase 11 Pre-Exposure Hardening Gate Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

section "Contracts & Governance"
markers=(
  "acceptance/PHASE11_ACCEPTED.md"
  "acceptance/PHASE11_PART1_ACCEPTED.md"
  "acceptance/PHASE11_PART2_ACCEPTED.md"
  "acceptance/PHASE11_PART3_ACCEPTED.md"
  "acceptance/PHASE11_PART4_ACCEPTED.md"
  "acceptance/PHASE11_PART5_ROUTING_ACCEPTED.md"
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

section "Identity & Access"
cmd="rg -n \"(^|\\s)(password|token|secret)\\s*:\\s\" contracts/tenants/**/consumers/**/enabled.yml"
if rg -n "(^|\s)(password|token|secret)\s*:\s" "${FABRIC_REPO_ROOT}/contracts/tenants" >/dev/null 2>&1; then
  fail "Enabled contracts contain no inline secrets" "${cmd}" "inline secret-like keys detected"
else
  pass "Enabled contracts contain no inline secrets" "${cmd}"
fi

cmd="rg -n \"secret_ref\" contracts/tenants/**/consumers/**/enabled.yml"
if rg -n "secret_ref" "${FABRIC_REPO_ROOT}/contracts/tenants" >/dev/null 2>&1; then
  pass "Enabled contracts declare secret_ref" "${cmd}"
else
  fail "Enabled contracts declare secret_ref" "${cmd}" "secret_ref not found"
fi

section "Tenant Isolation & Substrate Guardrails"
files=(
  "ops/substrate/capacity/capacity-guard.sh"
  "ops/substrate/validate-enabled-contracts.sh"
  "ops/substrate/common/execute-policy.yml"
  "ops/substrate/common/validate-execute-policy.sh"
)
for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

cmd="rg -n \"capacity-guard.sh\" ops/substrate/substrate.sh"
if rg -n "capacity-guard.sh" "${FABRIC_REPO_ROOT}/ops/substrate/substrate.sh" >/dev/null 2>&1; then
  pass "Capacity guard wired into substrate dispatcher" "${cmd}"
else
  fail "Capacity guard wired into substrate dispatcher" "${cmd}" "capacity guard not referenced"
fi

section "Capacity & Noisy-Neighbor"
files=(
  "contracts/tenants/_schema/capacity.schema.json"
  "contracts/tenants/_templates/capacity.yml"
  "ops/substrate/capacity/validate-capacity-semantics.sh"
)
for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

section "HA & Failure Semantics"
cmd="test -f ops/substrate/validate-enabled-contracts.sh"
if [[ -f "${FABRIC_REPO_ROOT}/ops/substrate/validate-enabled-contracts.sh" ]]; then
  pass "Enabled contract validation present" "${cmd}"
else
  fail "Enabled contract validation present" "${cmd}" "missing validator"
fi

section "Disaster Recovery Readiness"
dr_files=(
  "ops/substrate/postgres/dr-dryrun.sh"
  "ops/substrate/mariadb/dr-dryrun.sh"
  "ops/substrate/rabbitmq/dr-dryrun.sh"
  "ops/substrate/cache/dr-dryrun.sh"
  "ops/substrate/qdrant/dr-dryrun.sh"
)
for file in "${dr_files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "DR dry-run script present: ${file}" "${cmd}"
  else
    fail "DR dry-run script present: ${file}" "${cmd}" "missing dr-dryrun"
  fi
done

section "Observability & Drift"
obs_files=(
  "ops/substrate/observe/observe.sh"
  "ops/substrate/observe/compare.sh"
)
for file in "${obs_files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "Observability script present: ${file}" "${cmd}"
  else
    fail "Observability script present: ${file}" "${cmd}" "missing script"
  fi
done

section "Secrets & Sensitive Data"
cmd="test -f ops/secrets/secrets.sh"
if [[ -f "${FABRIC_REPO_ROOT}/ops/secrets/secrets.sh" ]]; then
  pass "Offline-first secrets interface present" "${cmd}"
else
  fail "Offline-first secrets interface present" "${cmd}" "missing secrets interface"
fi

cmd="rg -n \"^evidence/\" .gitignore"
if rg -n "^evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "Evidence directory is gitignored" "${cmd}"
else
  fail "Evidence directory is gitignored" "${cmd}" "evidence/ not ignored"
fi

section "Execution Safety"
pr_workflows=(
  "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml"
  "${FABRIC_REPO_ROOT}/.github/workflows/pr-tf-plan.yml"
)
for wf in "${pr_workflows[@]}"; do
  if [[ ! -f "${wf}" ]]; then
    fail "PR workflow present" "test -f ${wf}" "missing workflow"
  fi
  cmd="rg -n \"terraform apply|tf.apply|substrate.apply|tenants.apply\" ${wf}"
  if rg -n "terraform apply|tf.apply|substrate.apply|tenants.apply" "${wf}" >/dev/null 2>&1; then
    fail "PR workflow has no apply steps" "${cmd}" "apply command detected"
  else
    pass "PR workflow has no apply steps" "${cmd}"
  fi
done

cmd="rg -n \"workflow_dispatch\" .github/workflows/apply-nonprod.yml"
if [[ -f "${FABRIC_REPO_ROOT}/.github/workflows/apply-nonprod.yml" ]] && rg -n "workflow_dispatch" "${FABRIC_REPO_ROOT}/.github/workflows/apply-nonprod.yml" >/dev/null 2>&1; then
  pass "apply-nonprod workflow is manual" "${cmd}"
else
  fail "apply-nonprod workflow is manual" "${cmd}" "workflow_dispatch missing"
fi

section "Phase 12 Gating"
cmd="test ! -f acceptance/PHASE12_ACCEPTED.md"
if [[ -f "${FABRIC_REPO_ROOT}/acceptance/PHASE12_ACCEPTED.md" ]]; then
  fail "Phase 12 acceptance marker absent" "${cmd}" "Phase 12 acceptance marker present"
else
  pass "Phase 12 acceptance marker absent" "${cmd}"
fi

cmd="test ! -f acceptance/PHASE12_ENTRY_CHECKLIST.md"
if [[ -f "${FABRIC_REPO_ROOT}/acceptance/PHASE12_ENTRY_CHECKLIST.md" ]]; then
  fail "Phase 12 entry checklist absent" "${cmd}" "Phase 12 entry checklist present"
else
  pass "Phase 12 entry checklist absent" "${cmd}"
fi

cmd="rg -n \"phase12\" Makefile"
if rg -n "phase12" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  fail "No Phase 12 Makefile targets" "${cmd}" "phase12 targets detected"
else
  pass "No Phase 12 Makefile targets" "${cmd}"
fi

section "Operator UX & Docs"
cmd="rg -n \"phase11.hardening\" docs/operator/cookbook.md"
if rg -n "phase11.hardening" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook documents hardening gate" "${cmd}"
else
  fail "Cookbook documents hardening gate" "${cmd}" "hardening gate not documented"
fi

cmd="rg -n \"phase11.hardening\" OPERATIONS.md"
if rg -n "phase11.hardening" "${FABRIC_REPO_ROOT}/OPERATIONS.md" >/dev/null 2>&1; then
  pass "Operations doc references hardening gate" "${cmd}"
else
  fail "Operations doc references hardening gate" "${cmd}" "hardening gate not documented"
fi

section "Makefile Integration"
cmd="rg -n \"phase11.hardening.entry.check\" Makefile"
if rg -n "phase11.hardening.entry.check" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase11.hardening.entry.check" "${cmd}"
else
  fail "Makefile target present: phase11.hardening.entry.check" "${cmd}" "missing target"
fi

cmd="rg -n \"phase11.hardening.accept\" Makefile"
if rg -n "phase11.hardening.accept" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase11.hardening.accept" "${cmd}"
else
  fail "Makefile target present: phase11.hardening.accept" "${cmd}" "missing target"
fi
