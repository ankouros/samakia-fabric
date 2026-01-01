#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

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

require_env_name
require_dr_execute_guards
require_tools

"${FABRIC_REPO_ROOT}/ops/substrate/common/validate-execute-policy.sh"
"${FABRIC_REPO_ROOT}/ops/tenants/validate.sh"
"${FABRIC_REPO_ROOT}/ops/tenants/validate-consumer-bindings.sh"
"${FABRIC_REPO_ROOT}/ops/substrate/validate-enabled-contracts.sh"

if [[ "${ENV}" == "samakia-prod" ]]; then
  "${FABRIC_REPO_ROOT}/ops/substrate/common/change-window.sh"
fi

policy_json=$(cat "${FABRIC_REPO_ROOT}/ops/substrate/common/execute-policy.yml")
require_signing_for_prod=$(python3 - <<PY
import json
policy = json.loads('''${policy_json}''')
print("1" if policy.get("require_signing_for_prod", True) else "0")
PY
)

if [[ "${ENV}" == "samakia-prod" && "${require_signing_for_prod}" == "1" ]]; then
  if [[ "${EVIDENCE_SIGN:-0}" != "1" || -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
    echo "ERROR: prod DR execute requires EVIDENCE_SIGN=1 and EVIDENCE_SIGN_KEY" >&2
    exit 2
  fi
fi

if [[ -n "${EVIDENCE_SIGN_KEY:-}" && "${EVIDENCE_SIGN:-0}" != "1" ]]; then
  echo "ERROR: EVIDENCE_SIGN_KEY is set; set EVIDENCE_SIGN=1 to sign execute evidence" >&2
  exit 2
fi

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_for_tenant() {
  local tenant_dir="$1"
  local tenant_id="$2"

  local out_dir="${EVIDENCE_ROOT}/${tenant_id}/${stamp}/substrate-dr-execute"
  local backup_dir="${out_dir}/backup"
  local restore_dir="${out_dir}/restore"
  mkdir -p "${backup_dir}" "${restore_dir}"

  local items_file
  items_file="$(mktemp)"
  trap 'rm -f "${items_file}"' EXIT

  local contracts_json
  contracts_json="$(list_enabled_contracts "${tenant_dir}")"
  echo "${contracts_json}" | jq -c '.[]' | while read -r entry; do
    local consumer provider variant entry_file
    consumer=$(jq -r '.consumer' <<<"${entry}")
    provider=$(jq -r '.provider' <<<"${entry}")
    variant=$(jq -r '.variant' <<<"${entry}")

    "${FABRIC_REPO_ROOT}/ops/substrate/common/enforce-execute-policy.sh" \
      --tenant "${tenant_id}" --env "${ENV}" --consumer "${consumer}" --provider "${provider}" --variant "${variant}" --action dr

    entry_file="$(mktemp)"
    echo "${entry}" >"${entry_file}"

    local provider_backup_dir="${backup_dir}/${consumer}-${provider}-${variant}"
    local provider_restore_dir="${restore_dir}/${consumer}-${provider}-${variant}"
    mkdir -p "${provider_backup_dir}" "${provider_restore_dir}"

    "${FABRIC_REPO_ROOT}/ops/substrate/${provider}/backup.sh" \
      --entry "${entry_file}" --out "${provider_backup_dir}" --tenant "${tenant_id}" --stamp "${stamp}"

    "${FABRIC_REPO_ROOT}/ops/substrate/${provider}/restore.sh" \
      --entry "${entry_file}" --backup "${provider_backup_dir}" --out "${provider_restore_dir}" --tenant "${tenant_id}" --stamp "${stamp}"

    jq -n \
      --arg consumer "${consumer}" \
      --arg provider "${provider}" \
      --arg variant "${variant}" \
      --arg status "dr_executed" \
      '{consumer:$consumer,provider:$provider,variant:$variant,status:$status}' >>"${items_file}"

    rm -f "${entry_file}"
  done

  ITEMS_FILE="${items_file}" OUT_DIR="${out_dir}" TENANT_ID="${tenant_id}" STAMP="${stamp}" python3 - <<'PY'
import json
import os
from pathlib import Path

items = []
with open(os.environ["ITEMS_FILE"], "r") as handle:
    for line in handle:
        line = line.strip()
        if not line:
            continue
        items.append(json.loads(line))

out_dir = Path(os.environ["OUT_DIR"])
steps = {"tenant_id": os.environ["TENANT_ID"], "timestamp_utc": os.environ["STAMP"], "steps": items}
out_dir.mkdir(parents=True, exist_ok=True)
(out_dir / "steps.json").write_text(json.dumps(steps, indent=2, sort_keys=True) + "\n")
PY

  cat >"${out_dir}/report.md" <<EOF_REPORT
# Substrate DR Execute Evidence

Tenant: ${tenant_id}
Timestamp (UTC): ${stamp}

Executed entries: $(wc -l <"${items_file}")
EOF_REPORT

  write_metadata "${out_dir}" "${tenant_id}" "substrate-dr-execute" "${stamp}"
  write_manifest "${out_dir}"
  "${FABRIC_REPO_ROOT}/ops/substrate/common/signer.sh" "${out_dir}"

  echo "PASS substrate DR execute: ${out_dir}"
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
