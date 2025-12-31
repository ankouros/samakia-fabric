#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

env_file="${RUNNER_ENV_FILE:-${HOME}/.config/samakia-fabric/env.sh}"
if [[ -f "${env_file}" ]]; then
  # shellcheck disable=SC1090
  source "${env_file}"
fi

env_name="${POLICY_HA_ENV:-${ENV:-samakia-prod}}"

if [[ "${env_name}" != "samakia-minio" ]]; then
  bash "${FABRIC_REPO_ROOT}/ops/scripts/tf-backend-init.sh" "${env_name}"
fi

ENV="${env_name}" bash "${FABRIC_REPO_ROOT}/ops/scripts/ha/enforce-placement.sh" --env "${env_name}"
ENV="${env_name}" bash "${FABRIC_REPO_ROOT}/ops/scripts/ha/proxmox-ha-audit.sh" --enforce --env "${env_name}"
