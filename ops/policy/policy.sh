#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

policy_dir="${FABRIC_REPO_ROOT}/ops/policy"
env_file="${RUNNER_ENV_FILE:-${HOME}/.config/samakia-fabric/env.sh}"

if [[ -f "${env_file}" ]]; then
  # shellcheck disable=SC1090
  source "${env_file}"
fi

scripts=(
  "policy-terraform.sh"
  "policy-secrets.sh"
  "policy-secrets-materialization.sh"
  "policy-secrets-rotation.sh"
  "policy-ha.sh"
  "policy-docs.sh"
  "policy-security.sh"
  "policy-ai-ops.sh"
  "policy-ai-provider.sh"
  "policy-ai-routing.sh"
  "policy-drift.sh"
  "policy-runtime-eval.sh"
  "policy-slo.sh"
  "policy-alerts.sh"
  "policy-incidents.sh"
  "policy-bindings-verify.sh"
  "policy-proposals.sh"
  "policy-selfservice.sh"
  "policy-exposure.sh"
)

for script in "${scripts[@]}"; do
  path="${policy_dir}/${script}"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: policy script not found or not executable: ${path}" >&2
    exit 1
  fi
  echo "Running ${script}"
  bash "${path}"
done
