#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ "${FIREWALL_ENABLE:-0}" -eq 1 ]]; then
  echo "ERROR: FIREWALL_ENABLE=1 detected (default must remain OFF unless explicitly enabled for apply)" >&2
  exit 2
fi

bash "${FABRIC_REPO_ROOT}/ops/security/firewall/firewall-dryrun.sh"
