#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ $# -ne 1 ]]; then
  echo "usage: manifest.sh <evidence-dir>" >&2
  exit 2
fi

dir="$1"

if [[ ! -d "${dir}" ]]; then
  echo "ERROR: evidence dir not found: ${dir}" >&2
  exit 1
fi

(
  cd "${dir}"
  find . -type f ! -name "manifest.sha256" ! -name "manifest.sha256.asc" -print0 \
    | sort -z \
    | xargs -0 sha256sum > manifest.sha256
)
