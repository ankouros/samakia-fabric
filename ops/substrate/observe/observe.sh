#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/env.sh"

TENANT="${TENANT:-all}"
provider_filter="${PROVIDER_FILTER:-}"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_observe() {
  local tenant_dir="$1"
  local tenant_id="$2"
  local out_dir="${EVIDENCE_ROOT}/${tenant_id}/${stamp}/substrate-observe"

  PROVIDER_FILTER="${provider_filter}" "${FABRIC_REPO_ROOT}/ops/substrate/observe/observe-engine.sh" \
    "${tenant_dir}" "${tenant_id}" "${out_dir}" "${stamp}" >/dev/null
  echo "PASS substrate observe: ${out_dir}"
}

if [[ "${TENANT}" == "all" ]]; then
  for tenant_dir in "${TENANTS_ROOT}"/*; do
    [[ -d "${tenant_dir}" ]] || continue
    tenant_id="$(basename "${tenant_dir}")"
    run_observe "${tenant_dir}" "${tenant_id}"
  done
else
  tenant_dir="${TENANTS_ROOT}/${TENANT}"
  if [[ ! -d "${tenant_dir}" ]]; then
    echo "ERROR: tenant not found: ${TENANT}" >&2
    exit 1
  fi
  run_observe "${tenant_dir}" "${TENANT}"
fi
