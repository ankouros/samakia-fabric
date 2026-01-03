#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'USAGE'
Usage: restore.sh --entry <json> --backup <dir> --out <dir> --tenant <id> --stamp <timestamp>
USAGE
}

entry=""
backup_dir=""
out_dir=""
tenant_id=""
stamp=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --entry)
      entry="${2:-}"
      shift 2
      ;;
    --backup)
      backup_dir="${2:-}"
      shift 2
      ;;
    --out)
      out_dir="${2:-}"
      shift 2
      ;;
    --tenant)
      tenant_id="${2:-}"
      shift 2
      ;;
    --stamp)
      stamp="${2:-}"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${entry}" || -z "${backup_dir}" || -z "${out_dir}" || -z "${tenant_id}" || -z "${stamp}" ]]; then
  usage
  exit 2
fi

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/exec-lib.sh"

require_command pg_restore
require_command psql

local_json="$(cat "${entry}")"
host=$(jq -r '.endpoints.host' <<<"${local_json}")
port=$(jq -r '.endpoints.port' <<<"${local_json}")
secret_ref=$(jq -r '.secret_ref' <<<"${local_json}")
resources=$(jq -c '.resources' <<<"${local_json}")

db_name=$(python3 - <<PY
import json
print(json.loads('''${resources}''').get('database', '') or '')
PY
)

if [[ -z "${db_name}" ]]; then
  echo "ERROR: resources.database is required for postgres restore verification" >&2
  exit 2
fi

backup_file="${backup_dir}/${db_name}.dump"
if [[ ! -f "${backup_file}" ]]; then
  echo "ERROR: backup file not found: ${backup_file}" >&2
  exit 2
fi

secret_json=$(load_secret_json "${secret_ref}")
admin_user=$(get_secret_field "${secret_json}" "admin_username")
admin_pass=$(get_secret_field "${secret_json}" "admin_password")
if [[ -z "${admin_user}" ]]; then
  admin_user=$(get_secret_field "${secret_json}" "username")
  admin_pass=$(get_secret_field "${secret_json}" "password")
fi

if [[ -z "${admin_user}" || -z "${admin_pass}" ]]; then
  echo "ERROR: admin credentials missing in secret_ref ${secret_ref}" >&2
  exit 2
fi

mkdir -p "${out_dir}"

if [[ "${RESTORE_TO_TEMP_NAMESPACE:-0}" == "1" && "${I_UNDERSTAND_DESTRUCTIVE_RESTORE:-}" == "1" ]]; then
  temp_db="${db_name}_restore_${stamp//[:\-]/}"
  PGPASSWORD="${admin_pass}" psql -v ON_ERROR_STOP=1 -h "${host}" -p "${port}" -U "${admin_user}" -d postgres <<SQL
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${temp_db}') THEN
    CREATE DATABASE "${temp_db}" OWNER "${admin_user}";
  END IF;
END$$;
SQL

  PGPASSWORD="${admin_pass}" pg_restore -h "${host}" -p "${port}" -U "${admin_user}" -d "${temp_db}" "${backup_file}" >/dev/null
  PGPASSWORD="${admin_pass}" psql -v ON_ERROR_STOP=1 -h "${host}" -p "${port}" -U "${admin_user}" -d "${temp_db}" -c "SELECT 1;" >/dev/null

  PGPASSWORD="${admin_pass}" psql -v ON_ERROR_STOP=1 -h "${host}" -p "${port}" -U "${admin_user}" -d postgres -c "DROP DATABASE IF EXISTS \"${temp_db}\";" >/dev/null
  restore_mode="restore_to_temp"
else
  pg_restore --list "${backup_file}" >/dev/null
  restore_mode="integrity_only"
fi

python3 - <<PY
import json
from pathlib import Path

out = Path("${out_dir}")
out.mkdir(parents=True, exist_ok=True)
(out / "steps.json").write_text(json.dumps({"restore_mode": "${restore_mode}"}, indent=2, sort_keys=True) + "\n")
(out / "verification.json").write_text(json.dumps({"status": "verified"}, indent=2, sort_keys=True) + "\n")
PY

echo "PASS postgres restore verification (${restore_mode})"
