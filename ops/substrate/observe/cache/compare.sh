#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

TENANT="${TENANT:-all}" PROVIDER_FILTER="cache"   bash "${FABRIC_REPO_ROOT}/ops/substrate/observe/compare.sh"
