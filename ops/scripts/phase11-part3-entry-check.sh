#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE11_PART3_ENTRY_CHECKLIST.md"
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
# Phase 11 Part 3 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

marker="acceptance/PHASE11_PART2_ACCEPTED.md"
cmd="test -f ${marker}"
if [[ -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
  pass "Phase 11 Part 2 accepted" "${cmd}"
else
  fail "Phase 11 Part 2 accepted" "${cmd}" "missing Part 2 marker"
fi

if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
  fail "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md" "OPEN items found"
else
  pass "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md"
fi

files=(
  "contracts/tenants/_schema/capacity.schema.json"
  "contracts/tenants/_templates/capacity.yml"
  "contracts/tenants/examples/project-birds/capacity.yml"
  "contracts/tenants/examples/samakia-internal-tools/capacity.yml"
  "ops/substrate/capacity/validate-capacity-schema.sh"
  "ops/substrate/capacity/validate-capacity-semantics.sh"
  "ops/substrate/capacity/capacity-guard.sh"
  "ops/substrate/capacity/capacity-evidence.sh"
  "docs/substrate/capacity.md"
  "docs/substrate/slo-failure-semantics.md"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "tenants.capacity.validate" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: tenants.capacity.validate" "rg -n \"tenants.capacity.validate\" Makefile"
else
  fail "Makefile target present: tenants.capacity.validate" "rg -n \"tenants.capacity.validate\" Makefile" "missing target"
fi

if rg -n "substrate.capacity.guard" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: substrate.capacity.guard" "rg -n \"substrate.capacity.guard\" Makefile"
else
  fail "Makefile target present: substrate.capacity.guard" "rg -n \"substrate.capacity.guard\" Makefile" "missing target"
fi

if rg -n "substrate.capacity.evidence" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: substrate.capacity.evidence" "rg -n \"substrate.capacity.evidence\" Makefile"
else
  fail "Makefile target present: substrate.capacity.evidence" "rg -n \"substrate.capacity.evidence\" Makefile" "missing target"
fi

if rg -n "phase11.part3.entry.check" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase11.part3.entry.check" "rg -n \"phase11.part3.entry.check\" Makefile"
else
  fail "Makefile target present: phase11.part3.entry.check" "rg -n \"phase11.part3.entry.check\" Makefile" "missing target"
fi

if rg -n "phase11.part3.accept" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase11.part3.accept" "rg -n \"phase11.part3.accept\" Makefile"
else
  fail "Makefile target present: phase11.part3.accept" "rg -n \"phase11.part3.accept\" Makefile" "missing target"
fi

if rg -n "tenants.capacity.validate" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1; then
  pass "PR validation includes tenants.capacity.validate" "rg -n \"tenants.capacity.validate\" .github/workflows/pr-validate.yml"
else
  fail "PR validation includes tenants.capacity.validate" "rg -n \"tenants.capacity.validate\" .github/workflows/pr-validate.yml" "missing CI gate"
fi

if rg -n "substrate.capacity.guard" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1; then
  pass "PR validation includes substrate.capacity.guard" "rg -n \"substrate.capacity.guard\" .github/workflows/pr-validate.yml"
else
  fail "PR validation includes substrate.capacity.guard" "rg -n \"substrate.capacity.guard\" .github/workflows/pr-validate.yml" "missing CI gate"
fi

if rg -n "evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "Evidence paths gitignored" "rg -n \"evidence/\" .gitignore"
else
  fail "Evidence paths gitignored" "rg -n \"evidence/\" .gitignore" "missing gitignore rule"
fi
