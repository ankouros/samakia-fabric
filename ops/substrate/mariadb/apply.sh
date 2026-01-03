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

require_env_name
require_execute_guards
require_tools
require_command mysql

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
    echo "ERROR: prod execute requires EVIDENCE_SIGN=1 and EVIDENCE_SIGN_KEY" >&2
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

  local out_dir="${EVIDENCE_ROOT}/${tenant_id}/${stamp}/substrate-apply"
  mkdir -p "${out_dir}"

  local items_file
  items_file="$(mktemp)"
  trap 'rm -f "${items_file}"' EXIT

  local contracts_json
  contracts_json="$(list_enabled_contracts "${tenant_dir}" "mariadb")"
  echo "${contracts_json}" | jq -c '.[]' | while read -r entry; do
    local consumer provider variant host port secret_ref resources
    consumer=$(jq -r '.consumer' <<<"${entry}")
    provider=$(jq -r '.provider' <<<"${entry}")
    variant=$(jq -r '.variant' <<<"${entry}")
    host=$(jq -r '.endpoints.host' <<<"${entry}")
    port=$(jq -r '.endpoints.port' <<<"${entry}")
    secret_ref=$(jq -r '.secret_ref' <<<"${entry}")
    resources=$(jq -c '.resources' <<<"${entry}")

    "${FABRIC_REPO_ROOT}/ops/substrate/common/enforce-execute-policy.sh" \
      --tenant "${tenant_id}" --env "${ENV}" --consumer "${consumer}" --provider "${provider}" --variant "${variant}" --action apply

    if [[ "${resources}" == "{}" ]]; then
      echo "ERROR: resources are empty for ${tenant_id}/${consumer}/${provider}; specify database/user fields" >&2
      exit 2
    fi

    local secret_json admin_user admin_pass app_user app_pass db_name
    secret_json=$(load_secret_json "${secret_ref}")
    admin_user=$(get_secret_field "${secret_json}" "admin_username")
    admin_pass=$(get_secret_field "${secret_json}" "admin_password")
    if [[ -z "${admin_user}" ]]; then
      admin_user=$(get_secret_field "${secret_json}" "username")
      admin_pass=$(get_secret_field "${secret_json}" "password")
    fi

    app_user=$(python3 - <<PY
import json
print(json.loads('''${resources}''').get('user', '') or '')
PY
)
    app_pass=$(get_secret_field "${secret_json}" "app_password")
    if [[ -z "${app_user}" ]]; then
      app_user="${admin_user}"
      app_pass="${admin_pass}"
    fi

    db_name=$(python3 - <<PY
import json
print(json.loads('''${resources}''').get('database', '') or '')
PY
)

    if [[ -z "${db_name}" ]]; then
      echo "ERROR: resources.database is required for ${tenant_id}/${consumer}/${provider}" >&2
      exit 2
    fi

    if [[ -z "${admin_user}" || -z "${admin_pass}" ]]; then
      echo "ERROR: admin credentials missing in secret_ref ${secret_ref}" >&2
      exit 2
    fi

    MYSQL_PWD="${admin_pass}" mysql -h "${host}" -P "${port}" -u "${admin_user}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${db_name}\`;
CREATE USER IF NOT EXISTS '${app_user}'@'%' IDENTIFIED BY '${app_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${app_user}'@'%';
FLUSH PRIVILEGES;
SQL

    MYSQL_PWD="${admin_pass}" mysql -h "${host}" -P "${port}" -u "${admin_user}" -e "SELECT 1" "${db_name}" >/dev/null

    jq -n \
      --arg consumer "${consumer}" \
      --arg provider "${provider}" \
      --arg variant "${variant}" \
      --arg status "applied" \
      --arg database "${db_name}" \
      --arg user "${app_user}" \
      '{consumer:$consumer,provider:$provider,variant:$variant,status:$status,database:$database,user:$user}' >>"${items_file}"
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
plan = {"tenant_id": os.environ["TENANT_ID"], "timestamp_utc": os.environ["STAMP"], "plans": items}
actions = [{"consumer": i["consumer"], "provider": i["provider"], "variant": i["variant"], "actions": ["apply"]} for i in items]
results = items

out_dir.mkdir(parents=True, exist_ok=True)
(out_dir / "plan.json").write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
(out_dir / "actions.json").write_text(json.dumps(actions, indent=2, sort_keys=True) + "\n")
(out_dir / "results.json").write_text(json.dumps(results, indent=2, sort_keys=True) + "\n")
PY

  cat >"${out_dir}/report.md" <<EOF_REPORT
# Substrate Apply Evidence

Tenant: ${tenant_id}
Provider: mariadb
Timestamp (UTC): ${stamp}

Applied entries: $(wc -l <"${items_file}")
EOF_REPORT

  write_metadata "${out_dir}" "${tenant_id}" "substrate-apply" "${stamp}"
  write_manifest "${out_dir}"
  "${FABRIC_REPO_ROOT}/ops/substrate/common/signer.sh" "${out_dir}"

  echo "PASS substrate apply (mariadb): ${out_dir}"
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
