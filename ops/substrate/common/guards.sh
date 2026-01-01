#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

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
