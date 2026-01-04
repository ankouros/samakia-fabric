#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


dir="${1:-}"
if [[ -z "${dir}" ]]; then
  echo "usage: cutover-evidence.sh <dir>" >&2
  exit 2
fi

if [[ ! -d "${dir}" ]]; then
  echo "ERROR: evidence dir not found: ${dir}" >&2
  exit 2
fi

manifest="${dir}/manifest.sha256"
(
  cd "${dir}"
  find . -type f ! -name "manifest.sha256" ! -name "manifest.sha256.asc" -print0 | sort -z | xargs -0 sha256sum
) > "${manifest}"

if [[ "${EVIDENCE_SIGN:-0}" == "1" ]]; then
  bash "${FABRIC_REPO_ROOT}/ops/tenants/execute/signer.sh" "${manifest}"
fi
