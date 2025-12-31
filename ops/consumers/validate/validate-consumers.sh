#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

"${FABRIC_REPO_ROOT}/ops/consumers/validate/validate-schema.sh"
"${FABRIC_REPO_ROOT}/ops/consumers/validate/validate-semantics.sh"

echo "PASS: all consumer contracts validated"
