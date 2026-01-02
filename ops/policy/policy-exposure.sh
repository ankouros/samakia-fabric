#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: required file missing: ${path}" >&2
    exit 1
  fi
}

require_exec() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: required executable missing: ${path}" >&2
    exit 1
  fi
}

policy_dir="${FABRIC_REPO_ROOT}/ops/exposure/policy"
plan_dir="${FABRIC_REPO_ROOT}/ops/exposure/plan"
evidence_dir="${FABRIC_REPO_ROOT}/ops/exposure/evidence"

require_file "${FABRIC_REPO_ROOT}/contracts/exposure/exposure-policy.schema.json"
require_file "${FABRIC_REPO_ROOT}/contracts/exposure/exposure-policy.yml"

scripts=(
  "${policy_dir}/load.sh"
  "${policy_dir}/validate.sh"
  "${policy_dir}/evaluate.sh"
  "${policy_dir}/explain.sh"
  "${plan_dir}/plan.sh"
  "${plan_dir}/render.sh"
  "${plan_dir}/diff.sh"
  "${plan_dir}/redact.sh"
  "${evidence_dir}/generate.sh"
  "${evidence_dir}/manifest.sh"
  "${evidence_dir}/sign.sh"
)

for script in "${scripts[@]}"; do
  require_exec "${script}"
done

if [[ -d "${FABRIC_REPO_ROOT}/ops/exposure/apply" ]]; then
  echo "ERROR: apply path exists during Part 1 (plan-only)" >&2
  exit 1
fi

if rg -n "bindings\\.secrets|secrets\\.materialize|secrets\\.rotate|BIND_SECRETS" "${FABRIC_REPO_ROOT}/ops/exposure" >/dev/null 2>&1; then
  echo "ERROR: exposure plan must not invoke secrets interfaces" >&2
  exit 1
fi

if ! rg -n "EXPOSE_EXECUTE" "${plan_dir}/plan.sh" >/dev/null 2>&1; then
  echo "ERROR: plan execute guard missing" >&2
  exit 1
fi

if ! rg -n "prod_signing_required" "${policy_dir}/evaluate.sh" >/dev/null 2>&1; then
  echo "ERROR: prod signing enforcement missing in policy evaluation" >&2
  exit 1
fi

if ! rg -n "prod_change_window_required" "${policy_dir}/evaluate.sh" >/dev/null 2>&1; then
  echo "ERROR: change window enforcement missing in policy evaluation" >&2
  exit 1
fi

bash "${policy_dir}/validate.sh" >/dev/null

echo "policy-exposure: OK"
