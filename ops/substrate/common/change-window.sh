#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


start="${MAINT_WINDOW_START:-}"
end="${MAINT_WINDOW_END:-}"
max_minutes="${MAINT_WINDOW_MAX_MINUTES:-60}"

if [[ -z "${start}" || -z "${end}" ]]; then
  echo "ERROR: MAINT_WINDOW_START and MAINT_WINDOW_END are required" >&2
  exit 2
fi

"${FABRIC_REPO_ROOT}/ops/scripts/maint-window.sh" --start "${start}" --end "${end}" --max-minutes "${max_minutes}"
