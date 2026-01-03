#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'USAGE'
Usage: backup.sh --entry <json> --out <dir> --tenant <id> --stamp <timestamp>
USAGE
}

entry=""
out_dir=""
tenant_id=""
stamp=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --entry)
      entry="${2:-}"
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

if [[ -z "${entry}" || -z "${out_dir}" || -z "${tenant_id}" || -z "${stamp}" ]]; then
  usage
  exit 2
fi

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/exec-lib.sh"

require_command pg_dump

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
  echo "ERROR: resources.database is required for postgres backup" >&2
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
backup_file="${out_dir}/${db_name}.dump"

PGPASSWORD="${admin_pass}" pg_dump -Fc -h "${host}" -p "${port}" -U "${admin_user}" -f "${backup_file}" "${db_name}"

sha_file="${backup_file}.sha256"
sha256sum "${backup_file}" >"${sha_file}"

python3 - <<PY
import json
from pathlib import Path

out = Path("${out_dir}")
manifest = {
    "tenant_id": "${tenant_id}",
    "timestamp_utc": "${stamp}",
    "database": "${db_name}",
    "backup_file": Path("${backup_file}").name,
}
out.mkdir(parents=True, exist_ok=True)
(out / "artifact.manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
(out / "checks.json").write_text(json.dumps({"status": "backup_complete"}, indent=2, sort_keys=True) + "\n")
PY

echo "PASS postgres backup: ${backup_file}"
