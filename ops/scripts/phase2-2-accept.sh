#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ENV_NAME="${ENV:-samakia-shared}"

bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"

ENV="${ENV_NAME}" make shared.sdn.accept
ENV="${ENV_NAME}" make shared.ntp.accept
ENV="${ENV_NAME}" make shared.vault.accept
ENV="${ENV_NAME}" make shared.pki.accept
ENV="${ENV_NAME}" make shared.obs.accept
ENV="${ENV_NAME}" make shared.obs.ingest.accept
ENV="${ENV_NAME}" make shared.runtime.invariants.accept

echo "OK: Phase 2.2 acceptance passed"
