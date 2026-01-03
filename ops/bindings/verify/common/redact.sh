#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


redact_value() {
  local value="${1:-}"
  if [[ -z "${value}" ]]; then
    echo ""
    return
  fi
  local len=${#value}
  if [[ ${len} -le 4 ]]; then
    echo "***"
    return
  fi
  echo "${value:0:2}***${value: -2}"
}
