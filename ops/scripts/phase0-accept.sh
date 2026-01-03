#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

require_cmd pre-commit

echo "== Phase 0 acceptance (static checks) =="
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"

echo
echo "== Phase 0 acceptance (pre-commit) =="
pre-commit run --all-files

echo
echo "OK: Phase 0 acceptance passed"
