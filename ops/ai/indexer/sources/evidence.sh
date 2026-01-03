#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


mode="${INDEX_MODE:-offline}"

if [[ "${mode}" == "offline" ]]; then
  root="${FABRIC_REPO_ROOT}/ops/ai/indexer/fixtures/sample-evidence"
  find "${root}" -type f -print | sort
  exit 0
fi

if [[ ! -d "${FABRIC_REPO_ROOT}/evidence" ]]; then
  exit 0
fi

find "${FABRIC_REPO_ROOT}/evidence" -type f \( -name "*.md" -o -name "*.json" \) -print | sort
