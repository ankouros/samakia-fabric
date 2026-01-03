#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  echo "usage: validate-rollback.sh TENANT=<id> WORKLOAD=<id> ENV=<env>" >&2
}

tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"

if [[ -z "${tenant}" || -z "${workload}" || -z "${env_name}" ]]; then
  usage
  exit 2
fi

if [[ -z "${ROLLBACK_REASON:-}" ]]; then
  echo "ERROR: ROLLBACK_REASON is required" >&2
  exit 1
fi

if [[ "${ROLLBACK_EXECUTE:-0}" == "1" ]]; then
  if [[ "${CI:-0}" == "1" ]]; then
    echo "ERROR: rollback execute is not allowed in CI" >&2
    exit 2
  fi
fi

if [[ "${env_name}" == "samakia-prod" ]]; then
  if [[ -z "${CHANGE_WINDOW_START:-}" || -z "${CHANGE_WINDOW_END:-}" ]]; then
    echo "ERROR: prod rollback requires CHANGE_WINDOW_START and CHANGE_WINDOW_END" >&2
    exit 1
  fi
  if [[ "${EXPOSE_SIGN:-0}" != "1" ]]; then
    echo "ERROR: prod rollback requires EXPOSE_SIGN=1" >&2
    exit 1
  fi
  if [[ -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
    echo "ERROR: EVIDENCE_SIGN_KEY is required for prod signing" >&2
    exit 1
  fi
fi
