#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

PROVIDER_FILTER="mariadb" TENANT="${TENANT:-all}"   "${FABRIC_REPO_ROOT}/ops/substrate/observe/compare.sh"
