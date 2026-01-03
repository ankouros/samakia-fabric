#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


require_tools() {
  local missing=0
  for tool in "bash" "python3" "jq"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "ERROR: missing required tool: ${tool}" >&2
      missing=1
    fi
  done
  if [[ "${missing}" -ne 0 ]]; then
    exit 1
  fi
}

require_paths() {
  local missing=0
  for path in "$@"; do
    if [[ ! -e "${path}" ]]; then
      echo "ERROR: missing required path: ${path}" >&2
      missing=1
    fi
  done
  if [[ "${missing}" -ne 0 ]]; then
    exit 1
  fi
}

require_execute_guards() {
  if [[ "${TENANT_EXECUTE:-}" != "1" ]]; then
    echo "ERROR: TENANT_EXECUTE=1 is required for substrate apply" >&2
    exit 2
  fi
  if [[ "${I_UNDERSTAND_TENANT_MUTATION:-}" != "1" ]]; then
    echo "ERROR: I_UNDERSTAND_TENANT_MUTATION=1 is required for substrate apply" >&2
    exit 2
  fi
  if [[ -z "${EXECUTE_REASON:-}" ]]; then
    echo "ERROR: EXECUTE_REASON is required for substrate apply" >&2
    exit 2
  fi
}

require_dr_execute_guards() {
  if [[ "${DR_EXECUTE:-}" != "1" ]]; then
    echo "ERROR: DR_EXECUTE=1 is required for substrate DR execute" >&2
    exit 2
  fi
  require_execute_guards
}
