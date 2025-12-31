#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

TENANT="${TENANT:-all}"
TENANTS_ROOT="${FABRIC_REPO_ROOT}/contracts/tenants/examples"
EVIDENCE_ROOT="${FABRIC_REPO_ROOT}/evidence/tenants"

if [[ ! -d "${TENANTS_ROOT}" ]]; then
  echo "ERROR: tenant examples directory not found: ${TENANTS_ROOT}" >&2
  exit 1
fi

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

validate_all() {
  "${FABRIC_REPO_ROOT}/ops/tenants/validate-schema.sh"
  "${FABRIC_REPO_ROOT}/ops/tenants/validate-semantics.sh"
  "${FABRIC_REPO_ROOT}/ops/tenants/validate-policies.sh"
  "${FABRIC_REPO_ROOT}/ops/tenants/validate-consumer-bindings.sh"
}

write_result() {
  local dest="$1"
  local name="$2"
  local cmd="$3"
  python3 - <<PY
import json
from pathlib import Path

Path("${dest}").mkdir(parents=True, exist_ok=True)
data = {
  "check": "${name}",
  "command": "${cmd}",
  "status": "pass"
}
Path("${dest}/${name}.json").write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
}

write_metadata() {
  local dest="$1"
  local tenant_id="$2"
  python3 - <<PY
import json
from pathlib import Path

data = {
  "tenant_id": "${tenant_id}",
  "timestamp_utc": "${timestamp}",
  "git_commit": "$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
}
Path("${dest}/metadata.json").write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
}

write_report() {
  local dest="$1"
  local tenant_id="$2"
  cat >"${dest}/report.md" <<EOF
# Tenant Evidence Packet

Tenant: ${tenant_id}
Timestamp (UTC): ${timestamp}

## Checks
- schema: PASS
- semantics: PASS
- policies: PASS
- bindings: PASS
EOF
}

copy_inputs() {
  local src="$1"
  local dest="$2"
  mkdir -p "${dest}/inputs/consumers"
  for file in tenant.yml policies.yml quotas.yml endpoints.yml networks.yml; do
    local path="${src}/${file}"
    if [[ -f "${path}" ]]; then
      "${FABRIC_REPO_ROOT}/ops/tenants/redaction.sh" "${path}"
      cp "${path}" "${dest}/inputs/${file}"
    fi
  done
  if [[ -d "${src}/consumers" ]]; then
    find "${src}/consumers" -type f -name "ready.yml" | sort | while read -r ready; do
      "${FABRIC_REPO_ROOT}/ops/tenants/redaction.sh" "${ready}"
      rel="${ready#"${src}"/consumers/}"
      mkdir -p "${dest}/inputs/consumers/$(dirname "${rel}")"
      cp "${ready}" "${dest}/inputs/consumers/${rel}"
    done
  fi
}

finalize_manifest() {
  local dest="$1"
  (cd "${dest}" && find . -type f ! -name "manifest.sha256" -print0 | sort -z | xargs -0 sha256sum > manifest.sha256)
}

run_for_tenant() {
  local tenant_dir="$1"
  local tenant_id="$2"
  local dest="${EVIDENCE_ROOT}/${tenant_id}/${timestamp}"

  validate_all

  mkdir -p "${dest}/results"
  copy_inputs "${tenant_dir}" "${dest}"
  write_result "${dest}/results" "schema" "ops/tenants/validate-schema.sh"
  write_result "${dest}/results" "semantics" "ops/tenants/validate-semantics.sh"
  write_result "${dest}/results" "policies" "ops/tenants/validate-policies.sh"
  write_result "${dest}/results" "bindings" "ops/tenants/validate-consumer-bindings.sh"
  write_metadata "${dest}" "${tenant_id}"
  write_report "${dest}" "${tenant_id}"
  finalize_manifest "${dest}"

  echo "PASS evidence: ${dest}"
}

if [[ "${TENANT}" == "all" ]]; then
  for tenant_dir in "${TENANTS_ROOT}"/*; do
    [[ -d "${tenant_dir}" ]] || continue
    tenant_id="$(basename "${tenant_dir}")"
    run_for_tenant "${tenant_dir}" "${tenant_id}"
  done
  exit 0
fi

tenant_dir="${TENANTS_ROOT}/${TENANT}"
if [[ ! -d "${tenant_dir}" ]]; then
  echo "ERROR: tenant not found: ${tenant_dir}" >&2
  exit 1
fi

run_for_tenant "${tenant_dir}" "${TENANT}"
