#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/env.sh"
# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/evidence.sh"

TENANT="${TENANT:-all}"
provider_filter="${PROVIDER_FILTER:-}"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_compare() {
  local tenant_dir="$1"
  local tenant_id="$2"
  local out_dir="${EVIDENCE_ROOT}/${tenant_id}/${stamp}/substrate-observe"

  PROVIDER_FILTER="${provider_filter}" "${FABRIC_REPO_ROOT}/ops/substrate/observe/compare-engine.sh" \
    "${tenant_dir}" "${tenant_id}" "${out_dir}" "${stamp}" >/dev/null

  write_metadata "${out_dir}" "${tenant_id}" "substrate-observe" "${stamp}"
  write_manifest "${out_dir}"
  echo "PASS substrate observe compare: ${out_dir}"
}

if [[ "${TENANT}" == "all" ]]; then
  for tenant_dir in "${TENANTS_ROOT}"/*; do
    [[ -d "${tenant_dir}" ]] || continue
    tenant_id="$(basename "${tenant_dir}")"
    run_compare "${tenant_dir}" "${tenant_id}"
  done
else
  tenant_dir="${TENANTS_ROOT}/${TENANT}"
  if [[ ! -d "${tenant_dir}" ]]; then
    echo "ERROR: tenant not found: ${TENANT}" >&2
    exit 1
  fi
  run_compare "${tenant_dir}" "${TENANT}"
fi
