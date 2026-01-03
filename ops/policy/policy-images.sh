#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


bash "${FABRIC_REPO_ROOT}/ops/images/validate/validate-pinning.sh"
bash "${FABRIC_REPO_ROOT}/ops/images/validate/validate-apt-snapshot.sh"
bash "${FABRIC_REPO_ROOT}/ops/images/validate/validate-provenance.sh"
