#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


stamp="${RUNTIME_TIMESTAMP_UTC:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

if [[ -n "${OUT_PATH:-}" ]]; then
  printf '{"timestamp_utc": "%s"}\n' "${stamp}" > "${OUT_PATH}"
else
  echo "${stamp}"
fi
