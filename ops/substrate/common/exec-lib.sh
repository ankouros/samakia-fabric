#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/env.sh"

require_env_name() {
  if [[ -z "${ENV:-}" ]]; then
    echo "ERROR: ENV is required" >&2
    exit 2
  fi
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${cmd}" >&2
    exit 2
  fi
}

load_secret_json() {
  local secret_ref="$1"
  if [[ -z "${secret_ref}" ]]; then
    echo "ERROR: secret_ref is required" >&2
    exit 2
  fi
  local secret_json
  if ! secret_json=$(bash "${FABRIC_REPO_ROOT}/ops/secrets/secrets.sh" get "${secret_ref}"); then
    echo "ERROR: failed to load secret_ref: ${secret_ref}" >&2
    exit 2
  fi
  echo "${secret_json}"
}

get_secret_field() {
  local secret_json="$1"
  local field="$2"
  python3 - <<PY
import json
import sys

data = json.loads('''${secret_json}''')
field = "${field}"
if field not in data:
    print("", end="")
else:
    print(data[field], end="")
PY
}

try_load_secret_json() {
  local secret_ref="$1"
  if [[ -z "${secret_ref}" ]]; then
    return 1
  fi
  local secret_json
  if ! secret_json=$(bash "${FABRIC_REPO_ROOT}/ops/secrets/secrets.sh" get "${secret_ref}" 2>/dev/null); then
    return 1
  fi
  echo "${secret_json}"
  return 0
}
