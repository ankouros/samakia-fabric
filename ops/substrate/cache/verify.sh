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
source "${FABRIC_REPO_ROOT}/ops/substrate/common/contract.sh"
# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/evidence.sh"
# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/exec-lib.sh"
# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/connectivity.sh"

require_tools
require_paths "${TENANTS_ROOT}" "${DR_TAXONOMY}" "${FABRIC_REPO_ROOT}/ops/substrate/validate-enabled-contracts.sh"

"${FABRIC_REPO_ROOT}/ops/tenants/validate.sh"
"${FABRIC_REPO_ROOT}/ops/tenants/validate-consumer-bindings.sh"
"${FABRIC_REPO_ROOT}/ops/substrate/validate-enabled-contracts.sh"

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_for_tenant() {
  local tenant_dir="$1"
  local tenant_id="$2"

  local out_dir="${EVIDENCE_ROOT}/${tenant_id}/${stamp}/substrate-verify"
  mkdir -p "${out_dir}"

  local endpoints_file="${out_dir}/endpoints.json"
  local connectivity_file="${out_dir}/connectivity.json"

  local contracts_json
  contracts_json="$(list_enabled_contracts "${tenant_dir}" "dragonfly")"
  if [[ "$(echo "${contracts_json}" | jq 'length')" -eq 0 ]]; then
    echo "[]" >"${endpoints_file}"
  else
    echo "${contracts_json}" | jq -c '[.[] | {"key": (.consumer + ":" + .provider + ":" + .variant), "host": .endpoints.host, "port": .endpoints.port, "protocol": .endpoints.protocol}]' >"${endpoints_file}"
  fi

  connectivity_check "${endpoints_file}" "${connectivity_file}" "${stamp}"

  cat >"${out_dir}/report.md" <<EOF_REPORT
# Substrate Verify Evidence

Tenant: ${tenant_id}
Provider: dragonfly
Timestamp (UTC): ${stamp}

Contracts checked: $(echo "${contracts_json}" | jq 'length')
Connectivity results: ${connectivity_file}
EOF_REPORT

  write_metadata "${out_dir}" "${tenant_id}" "substrate-verify" "${stamp}"
  write_manifest "${out_dir}"

  echo "PASS substrate verify (dragonfly): ${out_dir}"
}

if [[ "${TENANT:-all}" == "all" ]]; then
  for tenant_dir in "${TENANTS_ROOT}"/*; do
    [[ -d "${tenant_dir}" ]] || continue
    tenant_id="$(basename "${tenant_dir}")"
    run_for_tenant "${tenant_dir}" "${tenant_id}"
  done
else
  tenant_dir="${TENANTS_ROOT}/${TENANT}"
  if [[ ! -d "${tenant_dir}" ]]; then
    echo "ERROR: tenant not found: ${TENANT}" >&2
    exit 1
  fi
  run_for_tenant "${tenant_dir}" "${TENANT}"
fi
