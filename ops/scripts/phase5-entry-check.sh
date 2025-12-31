#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE5_ENTRY_CHECKLIST.md"

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
# Phase 5 Entry Checklist

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

if [[ ! -f "${FABRIC_REPO_ROOT}/COMPLIANCE_CONTROLS.md" ]]; then
  fail "COMPLIANCE_CONTROLS.md present" "test -f COMPLIANCE_CONTROLS.md" "missing file"
else
  pass "COMPLIANCE_CONTROLS.md present" "test -f COMPLIANCE_CONTROLS.md"
fi

if ! rg -n "APP-" "${FABRIC_REPO_ROOT}/COMPLIANCE_CONTROLS.md" >/dev/null 2>&1; then
  fail "COMPLIANCE_CONTROLS.md parsable" "rg -n \"APP-\" COMPLIANCE_CONTROLS.md" "no control IDs found"
else
  pass "COMPLIANCE_CONTROLS.md parsable" "rg -n \"APP-\" COMPLIANCE_CONTROLS.md"
fi

if git -C "${FABRIC_REPO_ROOT}" ls-files | rg -n "(^ops/secrets/|^ops/security/ssh/.*\\.(key|pem|enc|pass)$|\\.enc$)" >/dev/null 2>&1; then
  fail "No secret files tracked" "git ls-files | rg -n <secret patterns>" "secret-like files tracked"
else
  pass "No secret files tracked" "git ls-files | rg -n <secret patterns>"
fi

scripts=(
  "ops/secrets/secrets.sh"
  "ops/secrets/secrets-file.sh"
  "ops/secrets/secrets-vault.sh"
  "ops/security/ssh/ssh-keys-generate.sh"
  "ops/security/ssh/ssh-keys-rotate.sh"
  "ops/security/ssh/ssh-keys-dryrun.sh"
  "ops/security/firewall/firewall-apply.sh"
  "ops/security/firewall/firewall-check.sh"
  "ops/security/firewall/firewall-dryrun.sh"
  "ops/scripts/compliance-eval.sh"
  "ops/policy/policy-security.sh"
)

for script in "${scripts[@]}"; do
  cmd="test -x ${script}"
  if [[ -x "${FABRIC_REPO_ROOT}/${script}" ]]; then
    pass "Script executable: ${script}" "${cmd}"
  else
    fail "Script executable: ${script}" "${cmd}" "missing or not executable"
  fi
done

workflows=(
  ".github/workflows/pr-validate.yml"
  ".github/workflows/pr-tf-plan.yml"
  ".github/workflows/apply-nonprod.yml"
  ".github/workflows/drift-detect.yml"
  ".github/workflows/app-compliance.yml"
  ".github/workflows/release-readiness.yml"
)

for wf in "${workflows[@]}"; do
  cmd="test -f ${wf}"
  if [[ -f "${FABRIC_REPO_ROOT}/${wf}" ]]; then
    pass "Workflow present: ${wf}" "${cmd}"
  else
    fail "Workflow present: ${wf}" "${cmd}" "missing workflow"
  fi
done

if make -C "${FABRIC_REPO_ROOT}" policy.check >/dev/null; then
  pass "Policy gates pass" "make policy.check"
else
  fail "Policy gates pass" "make policy.check" "policy.check failed"
fi
