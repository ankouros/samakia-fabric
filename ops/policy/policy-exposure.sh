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
approve_dir="${FABRIC_REPO_ROOT}/ops/exposure/approve"
apply_dir="${FABRIC_REPO_ROOT}/ops/exposure/apply"
verify_dir="${FABRIC_REPO_ROOT}/ops/exposure/verify"
rollback_dir="${FABRIC_REPO_ROOT}/ops/exposure/rollback"

require_file "${FABRIC_REPO_ROOT}/contracts/exposure/exposure-policy.schema.json"
require_file "${FABRIC_REPO_ROOT}/contracts/exposure/exposure-policy.yml"
require_file "${FABRIC_REPO_ROOT}/contracts/exposure/approval.schema.json"
require_file "${FABRIC_REPO_ROOT}/contracts/exposure/rollback.schema.json"

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
  "${approve_dir}/approve.sh"
  "${approve_dir}/reject.sh"
  "${approve_dir}/validate-approval.sh"
  "${apply_dir}/apply.sh"
  "${apply_dir}/validate-apply.sh"
  "${apply_dir}/write-artifacts.sh"
  "${apply_dir}/evidence.sh"
  "${apply_dir}/redact.sh"
  "${verify_dir}/verify.sh"
  "${verify_dir}/postcheck.sh"
  "${verify_dir}/drift-snapshot.sh"
  "${verify_dir}/evidence.sh"
  "${rollback_dir}/rollback.sh"
  "${rollback_dir}/validate-rollback.sh"
  "${rollback_dir}/evidence.sh"
)

for script in "${scripts[@]}"; do
  require_exec "${script}"
done

if rg -n "bindings\\.secrets|secrets\\.materialize|secrets\\.rotate|BIND_SECRETS" "${FABRIC_REPO_ROOT}/ops/exposure" >/dev/null 2>&1; then
  echo "ERROR: exposure plan must not invoke secrets interfaces" >&2
  exit 1
fi

if ! rg -n "EXPOSE_EXECUTE" "${plan_dir}/plan.sh" >/dev/null 2>&1; then
  echo "ERROR: plan execute guard missing" >&2
  exit 1
fi

if ! rg -n "EXPOSE_EXECUTE" "${apply_dir}/apply.sh" >/dev/null 2>&1; then
  echo "ERROR: apply execute guard missing" >&2
  exit 1
fi

if ! rg -n "ROLLBACK_EXECUTE" "${rollback_dir}/rollback.sh" >/dev/null 2>&1; then
  echo "ERROR: rollback execute guard missing" >&2
  exit 1
fi

if ! rg -n "VERIFY_LIVE" "${verify_dir}/verify.sh" >/dev/null 2>&1; then
  echo "ERROR: verify live guard missing" >&2
  exit 1
fi

if ! rg -n "CI" "${apply_dir}/apply.sh" >/dev/null 2>&1; then
  echo "ERROR: apply CI guard missing" >&2
  exit 1
fi

if ! rg -n "CI" "${rollback_dir}/rollback.sh" >/dev/null 2>&1; then
  echo "ERROR: rollback CI guard missing" >&2
  exit 1
fi

if ! rg -n "CI" "${verify_dir}/verify.sh" >/dev/null 2>&1; then
  echo "ERROR: verify CI guard missing" >&2
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
