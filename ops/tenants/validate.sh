#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


"${FABRIC_REPO_ROOT}/ops/tenants/validate-schema.sh"
"${FABRIC_REPO_ROOT}/ops/tenants/validate-semantics.sh"
"${FABRIC_REPO_ROOT}/ops/tenants/validate-policies.sh"
"${FABRIC_REPO_ROOT}/ops/tenants/validate-consumer-bindings.sh"
