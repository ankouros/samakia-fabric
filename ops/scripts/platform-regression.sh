#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


run_step() {
  local label="$1"
  shift
  echo "[platform.regression] ${label}"
  "$@"
}

run_step "Acceptance markers" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-platform/test-acceptance-markers.sh"
run_step "Policy gates" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-platform/test-policy-gates.sh"
run_step "No exec expansion" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-platform/test-no-exec-expansion.sh"
run_step "Go-live invariants" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-platform/test-go-live-invariants.sh"
run_step "Evidence index" bash "${FABRIC_REPO_ROOT}/ops/evidence/validate-index.sh"

echo "PASS: platform regression suite"
