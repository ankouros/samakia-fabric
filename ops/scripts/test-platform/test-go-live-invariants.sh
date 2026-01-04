#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


required=(
  "acceptance/PHASE16_ACCEPTED.md"
  "acceptance/PHASE13_ACCEPTED.md"
  "acceptance/PHASE17_STEP4_ACCEPTED.md"
  "acceptance/MILESTONE_PHASE1_12_ACCEPTED.md"
)

if [[ "${GO_LIVE_REQUIRED:-0}" == "1" ]]; then
  required+=("acceptance/GO_LIVE_ACCEPTED.md")
fi

missing=0
for marker in "${required[@]}"; do
  if [[ ! -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
    echo "ERROR: missing go-live invariant marker: ${marker}" >&2
    missing=1
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  exit 1
fi

invariants="${FABRIC_REPO_ROOT}/contracts/ai/INVARIANTS.md"
if [[ ! -f "${invariants}" ]]; then
  echo "ERROR: AI invariants file missing: ${invariants}" >&2
  exit 1
fi

if ! rg -n "analysis-only" "${invariants}" >/dev/null 2>&1; then
  echo "ERROR: AI invariants missing analysis-only statement" >&2
  exit 1
fi

if ! rg -n "zero execution authority" "${invariants}" >/dev/null 2>&1; then
  echo "ERROR: AI invariants missing zero execution authority statement" >&2
  exit 1
fi

if ! rg -n "Ollama" "${invariants}" >/dev/null 2>&1; then
  echo "ERROR: AI invariants missing provider statement" >&2
  exit 1
fi

echo "PASS: go-live invariants verified"
