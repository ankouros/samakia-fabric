#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

"${FABRIC_REPO_ROOT}/ops/tenants/validate-schema.sh"
"${FABRIC_REPO_ROOT}/ops/tenants/validate-semantics.sh"
