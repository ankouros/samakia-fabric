#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    die "missing required env var: ${name}"
  fi
}

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    die "missing required file: ${path}"
  fi
}

require_dir() {
  local path="$1"
  if [[ ! -d "${path}" ]]; then
    die "missing required directory: ${path}"
  fi
}

require_exec() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    die "missing required executable: ${path}"
  fi
}
