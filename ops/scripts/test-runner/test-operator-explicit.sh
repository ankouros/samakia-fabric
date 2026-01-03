#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" bash -c 'set -euo pipefail; source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"; require_operator_mode' 2>/dev/null; then
  fail "require_operator_mode should fail when RUNNER_MODE is unset or ci"
fi

if ! RUNNER_MODE=operator FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" bash -c 'set -euo pipefail; source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"; require_operator_mode'; then
  fail "require_operator_mode should pass when RUNNER_MODE=operator"
fi

if CI=1 RUNNER_MODE=operator FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" bash -c 'set -euo pipefail; source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"; require_operator_mode' 2>/dev/null; then
  fail "require_operator_mode should fail in CI"
fi

echo "PASS: operator mode requires explicit opt-in"
