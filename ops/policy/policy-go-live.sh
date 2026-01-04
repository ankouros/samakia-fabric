#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


missing=0

required=(
  "acceptance/GO_LIVE_ACCEPTED.md"
  "acceptance/PHASE8_3_ACCEPTED.md"
  "acceptance/PHASE17_STEP2_ACCEPTED.md"
  "acceptance/PHASE17_STEP3_ACCEPTED.md"
  "acceptance/PHASE17_STEP4_ACCEPTED.md"
  "acceptance/PHASE17_STEP5_ACCEPTED.md"
  "acceptance/PHASE17_STEP6_ACCEPTED.md"
  "acceptance/PHASE17_STEP7_ACCEPTED.md"
)

for marker in "${required[@]}"; do
  if [[ ! -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
    echo "ERROR: go-live gate missing marker: ${marker}" >&2
    missing=1
  fi
done

if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
  echo "ERROR: go-live gate blocked by OPEN items in REQUIRED-FIXES.md" >&2
  missing=1
fi

if [[ "${missing}" -ne 0 ]]; then
  exit 1
fi

echo "PASS: go-live policy gate"
