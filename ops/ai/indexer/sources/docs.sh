#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
mode="${INDEX_MODE:-offline}"
if [[ "${mode}" == "live" ]]; then
  require_operator_mode
else
  require_ci_mode
fi

if [[ "${mode}" == "offline" ]]; then
  root="${FABRIC_REPO_ROOT}/ops/ai/indexer/fixtures/sample-docs"
  find "${root}" -type f -print | sort | rg -v "/secret-note\\.md$"
  exit 0
fi

find "${FABRIC_REPO_ROOT}/docs" -type f -name "*.md" -print | sort
