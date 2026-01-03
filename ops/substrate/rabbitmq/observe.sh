#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


PROVIDER_FILTER="rabbitmq" TENANT="${TENANT:-all}"   "${FABRIC_REPO_ROOT}/ops/substrate/observe/observe.sh"
