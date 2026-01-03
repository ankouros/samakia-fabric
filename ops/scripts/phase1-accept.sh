#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


ENV_NAME="${ENV:-samakia-prod}"

echo "== Phase 1 acceptance (static checks) =="
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"

echo
echo "== Phase 1 acceptance (guardrails) =="
bash "${FABRIC_REPO_ROOT}/ops/scripts/env-parity-check.sh"
bash "${FABRIC_REPO_ROOT}/ops/scripts/runner-env-check.sh"

echo
echo "== Phase 1 acceptance (inventory) =="
ENV="${ENV_NAME}" make inventory.check

echo
echo "== Phase 1 acceptance (terraform plan; non-interactive) =="
ENV="${ENV_NAME}" make tf.plan CI=1

echo
echo "OK: Phase 1 acceptance passed"
