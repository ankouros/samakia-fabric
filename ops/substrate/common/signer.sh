#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  echo "usage: signer.sh <dir-with-manifest>" >&2
}

dir="${1:-}"
if [[ -z "${dir}" ]]; then
  usage
  exit 2
fi

manifest="${dir}/manifest.sha256"
if [[ ! -f "${manifest}" ]]; then
  echo "ERROR: manifest not found: ${manifest}" >&2
  exit 2
fi

if [[ "${EVIDENCE_SIGN:-0}" != "1" ]]; then
  echo "INFO: signing skipped (EVIDENCE_SIGN not enabled)"
  exit 0
fi

if [[ -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
  echo "ERROR: EVIDENCE_SIGN_KEY is required when EVIDENCE_SIGN=1" >&2
  exit 2
fi

if ! command -v gpg >/dev/null 2>&1; then
  echo "ERROR: gpg not available for signing" >&2
  exit 2
fi

gpg --batch --yes --local-user "${EVIDENCE_SIGN_KEY}" --output "${manifest}.asc" --detach-sign "${manifest}"

echo "INFO: signed manifest: ${manifest}.asc"
