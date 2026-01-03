#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ "${ROTATE_EXECUTE:-0}" != "1" ]]; then
  echo "ERROR: ROTATE_EXECUTE=1 required to rotate credentials" >&2
  exit 2
fi

TENANT_CREDS_ISSUE=1 \
  bash "${FABRIC_REPO_ROOT}/ops/tenants/creds/issue.sh" "$@"
