#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"

unset RUNNER_MODE
unset CI
unset INTERACTIVE

require_ci_mode

if [[ "${RUNNER_MODE}" != "ci" ]]; then
  echo "FAIL: RUNNER_MODE default is not ci (got '${RUNNER_MODE}')." >&2
  exit 1
fi

echo "PASS: default RUNNER_MODE=ci"
