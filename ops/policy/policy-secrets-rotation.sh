#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR: rg not found (required for policy checks)" >&2
  exit 1
fi

require_exec() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: missing or non-executable: ${path}" >&2
    exit 1
  fi
}

rotate="${FABRIC_REPO_ROOT}/ops/bindings/rotate/rotate.sh"
rotate_dryrun="${FABRIC_REPO_ROOT}/ops/bindings/rotate/rotate-dryrun.sh"
rotate_plan="${FABRIC_REPO_ROOT}/ops/bindings/rotate/rotate-plan.sh"
rotate_evidence="${FABRIC_REPO_ROOT}/ops/bindings/rotate/rotate-evidence.sh"

require_exec "${rotate}"
require_exec "${rotate_dryrun}"
require_exec "${rotate_plan}"
require_exec "${rotate_evidence}"

if ! rg -n "ROTATE_EXECUTE" "${rotate}" >/dev/null; then
  echo "ERROR: rotation guard missing (ROTATE_EXECUTE)" >&2
  exit 1
fi

if ! rg -n "ROTATE_REASON" "${rotate}" >/dev/null; then
  echo "ERROR: rotation guard missing (ROTATE_REASON)" >&2
  exit 1
fi

if ! rg -n "change-window.sh" "${rotate}" >/dev/null; then
  echo "ERROR: rotation must enforce change window for prod" >&2
  exit 1
fi

if ! rg -n "evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null; then
  echo "ERROR: evidence paths must be gitignored" >&2
  exit 1
fi

exit 0
