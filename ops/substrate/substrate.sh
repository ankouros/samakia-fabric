#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/env.sh"
# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/guards.sh"
# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/plan-format.sh"
# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/contract.sh"

usage() {
  cat <<'USAGE'
Usage: substrate.sh <command> [TENANT=<id|all>]

Commands:
  plan
  dr-dryrun
  apply
  verify
  dr-execute
  doctor
USAGE
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

cmd="$1"
shift || true

for arg in "$@"; do
  if [[ "${arg}" == TENANT=* ]]; then
    TENANT="${arg#TENANT=}"
  fi
  if [[ "${arg}" == PROVIDER=* ]]; then
    SUBSTRATE_PROVIDER="${arg#PROVIDER=}"
  fi
done

TENANT="${TENANT:-all}"
provider_filter="${SUBSTRATE_PROVIDER:-}"

run_for_tenant() {
  local tenant_dir="$1"
  local tenant_id="$2"
  local stamp="$3"
  local provider_dir=""

  if [[ "${cmd}" == "plan" ]]; then
    local out_dir="${EVIDENCE_ROOT}/${tenant_id}/${stamp}/substrate-plan"
    generate_plan "${tenant_dir}" "${tenant_id}" "${out_dir}" "${provider_filter}" "${stamp}"
    write_metadata "${out_dir}" "${tenant_id}" "substrate-plan" "${stamp}"
    write_manifest "${out_dir}"
    echo "PASS substrate plan: ${out_dir}"
    return
  fi

  if [[ "${cmd}" == "dr-dryrun" ]]; then
    local out_dir="${EVIDENCE_ROOT}/${tenant_id}/${stamp}/substrate-dr-dryrun"
    generate_dr_dryrun "${tenant_dir}" "${tenant_id}" "${out_dir}" "${provider_filter}" "${stamp}"
    write_metadata "${out_dir}" "${tenant_id}" "substrate-dr-dryrun" "${stamp}"
    write_manifest "${out_dir}"
    echo "PASS substrate DR dry-run: ${out_dir}"
    return
  fi

  if [[ "${cmd}" == "apply" ]]; then
    if [[ -n "${stamp}" ]]; then
      CAPACITY_EVIDENCE_ROOT="${EVIDENCE_ROOT}" CAPACITY_STAMP="${stamp}" TENANT="${tenant_id}" \
        bash "${FABRIC_REPO_ROOT}/ops/substrate/capacity/capacity-guard.sh"
    fi
    local contracts_json providers
    contracts_json="$(list_enabled_contracts "${tenant_dir}" "${provider_filter}")"
    providers="$(echo "${contracts_json}" | jq -r '.[].provider' | sort -u)"
    if [[ -z "${providers}" ]]; then
      echo "WARN substrate apply: no enabled contracts for tenant ${tenant_id}"
      return
    fi
    for provider in ${providers}; do
      provider_dir="${provider}"
      if [[ "${provider}" == "dragonfly" ]]; then
        provider_dir="cache"
      fi
      TENANT="${tenant_id}" bash "${FABRIC_REPO_ROOT}/ops/substrate/${provider_dir}/apply.sh"
    done
    return
  fi

  if [[ "${cmd}" == "verify" ]]; then
    local contracts_json providers
    contracts_json="$(list_enabled_contracts "${tenant_dir}" "${provider_filter}")"
    providers="$(echo "${contracts_json}" | jq -r '.[].provider' | sort -u)"
    if [[ -z "${providers}" ]]; then
      echo "WARN substrate verify: no enabled contracts for tenant ${tenant_id}"
      return
    fi
    for provider in ${providers}; do
      provider_dir="${provider}"
      if [[ "${provider}" == "dragonfly" ]]; then
        provider_dir="cache"
      fi
      TENANT="${tenant_id}" bash "${FABRIC_REPO_ROOT}/ops/substrate/${provider_dir}/verify.sh"
    done
    return
  fi
}

case "${cmd}" in
  plan|dr-dryrun)
    require_tools
    require_paths "${TENANTS_ROOT}" "${DR_TAXONOMY}" "${FABRIC_REPO_ROOT}/ops/substrate/validate-enabled-contracts.sh"

    "${FABRIC_REPO_ROOT}/ops/tenants/validate.sh"
    "${FABRIC_REPO_ROOT}/ops/tenants/validate-consumer-bindings.sh"
    "${FABRIC_REPO_ROOT}/ops/substrate/validate-enabled-contracts.sh"

    stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if [[ "${TENANT}" == "all" ]]; then
      for tenant_dir in "${TENANTS_ROOT}"/*; do
        [[ -d "${tenant_dir}" ]] || continue
        tenant_id="$(basename "${tenant_dir}")"
        run_for_tenant "${tenant_dir}" "${tenant_id}" "${stamp}"
      done
    else
      tenant_dir="${TENANTS_ROOT}/${TENANT}"
      if [[ ! -d "${tenant_dir}" ]]; then
        echo "ERROR: tenant not found: ${TENANT}" >&2
        exit 1
      fi
      run_for_tenant "${tenant_dir}" "${TENANT}" "${stamp}"
    fi
    ;;
  apply|verify)
    require_tools
    require_paths "${TENANTS_ROOT}" "${DR_TAXONOMY}" "${FABRIC_REPO_ROOT}/ops/substrate/validate-enabled-contracts.sh"

    "${FABRIC_REPO_ROOT}/ops/tenants/validate.sh"
    "${FABRIC_REPO_ROOT}/ops/tenants/validate-consumer-bindings.sh"
    "${FABRIC_REPO_ROOT}/ops/substrate/validate-enabled-contracts.sh"

    stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if [[ "${TENANT}" == "all" ]]; then
      for tenant_dir in "${TENANTS_ROOT}"/*; do
        [[ -d "${tenant_dir}" ]] || continue
        tenant_id="$(basename "${tenant_dir}")"
        run_for_tenant "${tenant_dir}" "${tenant_id}" "${stamp}"
      done
    else
      tenant_dir="${TENANTS_ROOT}/${TENANT}"
      if [[ ! -d "${tenant_dir}" ]]; then
        echo "ERROR: tenant not found: ${TENANT}" >&2
        exit 1
      fi
      run_for_tenant "${tenant_dir}" "${TENANT}" "${stamp}"
    fi
    ;;
  dr-execute)
    if [[ -n "${provider_filter}" ]]; then
      echo "ERROR: dr-execute does not support PROVIDER filter" >&2
      exit 1
    fi
    if [[ -n "${TENANT:-}" ]]; then
      TENANT="${TENANT}" bash "${FABRIC_REPO_ROOT}/ops/substrate/common/dr-run.sh"
    else
      bash "${FABRIC_REPO_ROOT}/ops/substrate/common/dr-run.sh"
    fi
    ;;
  doctor)
    require_tools
    require_paths "${TENANTS_ROOT}" "${DR_TAXONOMY}" \
      "${FABRIC_REPO_ROOT}/ops/tenants/validate.sh" \
      "${FABRIC_REPO_ROOT}/ops/tenants/validate-consumer-bindings.sh" \
      "${FABRIC_REPO_ROOT}/ops/substrate/validate-enabled-contracts.sh"

    "${FABRIC_REPO_ROOT}/ops/tenants/validate.sh"
    "${FABRIC_REPO_ROOT}/ops/tenants/validate-consumer-bindings.sh"
    "${FABRIC_REPO_ROOT}/ops/substrate/validate-enabled-contracts.sh"

    echo "PASS substrate doctor: tooling and contracts present"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
