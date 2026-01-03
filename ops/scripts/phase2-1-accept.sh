#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


ENV_NAME="${ENV:-samakia-shared}"

bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"

ENV="${ENV_NAME}" make shared.sdn.accept
ENV="${ENV_NAME}" make shared.ntp.accept
ENV="${ENV_NAME}" make shared.vault.accept
ENV="${ENV_NAME}" make shared.pki.accept
ENV="${ENV_NAME}" make shared.obs.policy
ENV="${ENV_NAME}" make shared.obs.accept

echo "OK: Phase 2.1 acceptance passed"
