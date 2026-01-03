#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


SUBSTRATE_ROOT="${FABRIC_REPO_ROOT}/ops/substrate"
TENANTS_ROOT_DEFAULT="${FABRIC_REPO_ROOT}/contracts/tenants/examples"
TENANTS_ROOT="${TENANTS_ROOT:-${TENANTS_ROOT_DEFAULT}}"
DR_TAXONOMY="${FABRIC_REPO_ROOT}/contracts/substrate/dr-testcases.yml"
EVIDENCE_ROOT="${FABRIC_REPO_ROOT}/evidence/tenants"

export SUBSTRATE_ROOT TENANTS_ROOT TENANTS_ROOT_DEFAULT DR_TAXONOMY EVIDENCE_ROOT
