#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

"${FABRIC_REPO_ROOT}/ops/substrate/observe/normalize-json.sh" "$@"
