#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

"${FABRIC_REPO_ROOT}/ops/docs/operator-inventory.sh"
"${FABRIC_REPO_ROOT}/ops/docs/cookbook-lint.sh"

echo "PASS: docs anti-drift checks"
