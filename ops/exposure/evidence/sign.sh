#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ $# -ne 2 ]]; then
  echo "usage: sign.sh <env> <evidence-dir>" >&2
  exit 2
fi

env_name="$1"
dir="$2"

manifest="${dir}/manifest.sha256"
if [[ ! -f "${manifest}" ]]; then
  echo "ERROR: manifest not found: ${manifest}" >&2
  exit 1
fi

sign_required=0
if [[ "${env_name}" == "samakia-prod" || "${EXPOSURE_SIGN:-0}" == "1" ]]; then
  sign_required=1
fi

if [[ "${sign_required}" -ne 1 ]]; then
  echo "INFO: signing not required" >&2
  exit 0
fi

EVIDENCE_SIGN=1 EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  bash "${FABRIC_REPO_ROOT}/ops/tenants/execute/signer.sh" "${manifest}"
