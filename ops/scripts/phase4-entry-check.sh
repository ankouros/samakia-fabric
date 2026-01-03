#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out="${FABRIC_REPO_ROOT}/acceptance/PHASE4_ENTRY_CHECKLIST.md"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

pass() { echo "- Result: PASS"; }
fail() { echo "- Result: FAIL"; }

if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR: rg is required for entry checks" >&2
  exit 1
fi

{
  echo "# Phase 4 Entry Checklist"
  echo
  echo "Timestamp (UTC): ${now}"
  echo
  echo "## Criteria"
  echo
  echo "1) Phase 0 acceptance marker present"
  echo "- Command: test -f acceptance/PHASE0_ACCEPTED.md"
  if test -f "${FABRIC_REPO_ROOT}/acceptance/PHASE0_ACCEPTED.md"; then pass; else fail; fi
  echo
  echo "2) Phase 1 acceptance marker present"
  echo "- Command: test -f acceptance/PHASE1_ACCEPTED.md"
  if test -f "${FABRIC_REPO_ROOT}/acceptance/PHASE1_ACCEPTED.md"; then pass; else fail; fi
  echo
  echo "3) Phase 2 acceptance marker present"
  echo "- Command: test -f acceptance/PHASE2_ACCEPTED.md"
  if test -f "${FABRIC_REPO_ROOT}/acceptance/PHASE2_ACCEPTED.md"; then pass; else fail; fi
  echo
  echo "4) Phase 2.1 acceptance marker present"
  echo "- Command: test -f acceptance/PHASE2_1_ACCEPTED.md"
  if test -f "${FABRIC_REPO_ROOT}/acceptance/PHASE2_1_ACCEPTED.md"; then pass; else fail; fi
  echo
  echo "5) Phase 2.2 acceptance marker present"
  echo "- Command: test -f acceptance/PHASE2_2_ACCEPTED.md"
  if test -f "${FABRIC_REPO_ROOT}/acceptance/PHASE2_2_ACCEPTED.md"; then pass; else fail; fi
  echo
  echo "6) Phase 3 Part 1 acceptance marker present"
  echo "- Command: test -f acceptance/PHASE3_PART1_ACCEPTED.md"
  if test -f "${FABRIC_REPO_ROOT}/acceptance/PHASE3_PART1_ACCEPTED.md"; then pass; else fail; fi
  echo
  echo "7) Phase 3 Part 2 acceptance marker present"
  echo "- Command: test -f acceptance/PHASE3_PART2_ACCEPTED.md"
  if test -f "${FABRIC_REPO_ROOT}/acceptance/PHASE3_PART2_ACCEPTED.md"; then pass; else fail; fi
  echo
  echo "8) Phase 3 Part 3 acceptance marker present"
  echo "- Command: test -f acceptance/PHASE3_PART3_ACCEPTED.md"
  if test -f "${FABRIC_REPO_ROOT}/acceptance/PHASE3_PART3_ACCEPTED.md"; then pass; else fail; fi
  echo
  echo "9) REQUIRED-FIXES.md has no OPEN items"
  echo "- Command: rg -n \"OPEN\" REQUIRED-FIXES.md"
  if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then fail; else echo "- Result: PASS (no matches)"; fi
  echo
  echo "10) CI workflows present"
  echo "- Command: test -f .github/workflows/{pr-validate.yml,pr-tf-plan.yml,apply-nonprod.yml,drift-detect.yml,app-compliance.yml,release-readiness.yml}"
  if test -f "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" \
    && test -f "${FABRIC_REPO_ROOT}/.github/workflows/pr-tf-plan.yml" \
    && test -f "${FABRIC_REPO_ROOT}/.github/workflows/apply-nonprod.yml" \
    && test -f "${FABRIC_REPO_ROOT}/.github/workflows/drift-detect.yml" \
    && test -f "${FABRIC_REPO_ROOT}/.github/workflows/app-compliance.yml" \
    && test -f "${FABRIC_REPO_ROOT}/.github/workflows/release-readiness.yml"; then pass; else fail; fi
  echo
  echo "11) CI workflows reference policy/checks"
  echo "- Command: rg -n <required patterns> .github/workflows"
  if rg -n "make policy.check" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1 \
    && rg -n "pre-commit run --all-files" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1 \
    && rg -n "fabric-ci/scripts/lint.sh" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1 \
    && rg -n "fabric-ci/scripts/validate.sh" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1 \
    && rg -n "make ha.enforce.check" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1; then
    pass
  else
    fail
  fi
  echo
  echo "12) CI plan matrix includes required envs"
  echo "- Command: rg -n \"samakia-\" .github/workflows/pr-tf-plan.yml"
  if rg -n "samakia-dev" "${FABRIC_REPO_ROOT}/.github/workflows/pr-tf-plan.yml" >/dev/null 2>&1 \
    && rg -n "samakia-staging" "${FABRIC_REPO_ROOT}/.github/workflows/pr-tf-plan.yml" >/dev/null 2>&1 \
    && rg -n "samakia-prod" "${FABRIC_REPO_ROOT}/.github/workflows/pr-tf-plan.yml" >/dev/null 2>&1 \
    && rg -n "samakia-dns" "${FABRIC_REPO_ROOT}/.github/workflows/pr-tf-plan.yml" >/dev/null 2>&1 \
    && rg -n "samakia-minio" "${FABRIC_REPO_ROOT}/.github/workflows/pr-tf-plan.yml" >/dev/null 2>&1 \
    && rg -n "samakia-shared" "${FABRIC_REPO_ROOT}/.github/workflows/pr-tf-plan.yml" >/dev/null 2>&1; then
    pass
  else
    fail
  fi
  echo
  echo "13) Apply workflow gating (non-prod only + confirm phrase)"
  echo "- Command: rg -n <allowlist + confirm phrase> .github/workflows/apply-nonprod.yml"
  if rg -n "I_UNDERSTAND_APPLY_IS_MUTATING" "${FABRIC_REPO_ROOT}/.github/workflows/apply-nonprod.yml" >/dev/null 2>&1 \
    && rg -n "samakia-dev" "${FABRIC_REPO_ROOT}/.github/workflows/apply-nonprod.yml" >/dev/null 2>&1 \
    && rg -n "samakia-staging" "${FABRIC_REPO_ROOT}/.github/workflows/apply-nonprod.yml" >/dev/null 2>&1 \
    && ! rg -n "samakia-prod" "${FABRIC_REPO_ROOT}/.github/workflows/apply-nonprod.yml" >/dev/null 2>&1; then
    pass
  else
    fail
  fi
  echo
  echo "14) Policy gates pass locally"
  echo "- Command: make policy.check"
  if (cd "${FABRIC_REPO_ROOT}" && make policy.check) >/dev/null 2>&1; then
    pass
  else
    fail
  fi
  echo
  echo "Notes:"
  echo "- If any criterion fails, Phase 4 work must stop and remediation must be recorded in REQUIRED-FIXES.md."
} >"${out}"

printf "Wrote %s\n" "${out}"
