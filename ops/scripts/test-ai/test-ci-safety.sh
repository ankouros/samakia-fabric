#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


analysis_script="${FABRIC_REPO_ROOT}/ops/ai/analysis/analyze.sh"
call_script="${FABRIC_REPO_ROOT}/ops/ai/analysis/call-ollama.sh"

for script in "${analysis_script}" "${call_script}"; do
  if ! rg -n "blocked in CI" "${script}" >/dev/null 2>&1; then
    echo "ERROR: CI guard missing in ${script}" >&2
    exit 1
  fi
  if ! rg -n "AI_ANALYZE_EXECUTE" "${script}" >/dev/null 2>&1; then
    echo "ERROR: execute guard missing in ${script}" >&2
    exit 1
  fi
done

echo "PASS: CI safety guards present"
