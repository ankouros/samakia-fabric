#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

"${FABRIC_REPO_ROOT}/ops/substrate/validate-dr-taxonomy.sh"
"${FABRIC_REPO_ROOT}/ops/substrate/validate-enabled-contracts.sh"
