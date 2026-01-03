#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

mode="${INDEX_MODE:-offline}"

if [[ "${mode}" == "offline" ]]; then
  root="${FABRIC_REPO_ROOT}/ops/ai/indexer/fixtures/sample-contracts"
  find "${root}" -type f -print | sort
  exit 0
fi

find "${FABRIC_REPO_ROOT}/contracts" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) -print | sort
