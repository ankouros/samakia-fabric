#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ -z "${EVIDENCE_DIR:-}" ]]; then
  echo "ERROR: EVIDENCE_DIR is required" >&2
  exit 2
fi

if [[ ! -d "${EVIDENCE_DIR}" ]]; then
  echo "ERROR: evidence dir not found: ${EVIDENCE_DIR}" >&2
  exit 2
fi

(
  cd "${EVIDENCE_DIR}"
  find . -type f \
    ! -name "manifest.sha256" \
    ! -name "manifest.sha256.asc" \
    -print0 \
    | sort -z \
    | xargs -0 sha256sum > manifest.sha256
)

bash "${FABRIC_REPO_ROOT}/ops/substrate/common/signer.sh" "${EVIDENCE_DIR}"
