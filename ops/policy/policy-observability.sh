#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

env_name="${ENV:-samakia-shared}"
validate_dir="${FABRIC_REPO_ROOT}/ops/observability/validate"

bash "${validate_dir}/validate-policy.sh"
ENV="${env_name}" bash "${validate_dir}/validate-replicas.sh"
ENV="${env_name}" bash "${validate_dir}/validate-affinity.sh"

echo "PASS: observability policy enforced"
