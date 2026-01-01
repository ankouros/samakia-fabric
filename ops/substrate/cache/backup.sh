#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

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

require_command redis-cli

local_json="$(cat "${entry}")"
host=$(jq -r '.endpoints.host' <<<"${local_json}")
port=$(jq -r '.endpoints.port' <<<"${local_json}")
secret_ref=$(jq -r '.secret_ref' <<<"${local_json}")

secret_json=$(load_secret_json "${secret_ref}")
auth_pass=$(get_secret_field "${secret_json}" "password")
if [[ -z "${auth_pass}" ]]; then
  auth_pass=$(get_secret_field "${secret_json}" "auth")
fi

if [[ -z "${auth_pass}" ]]; then
  echo "ERROR: cache credentials missing in secret_ref ${secret_ref}" >&2
  exit 2
fi

mkdir -p "${out_dir}"
backup_file="${out_dir}/dragonfly.rdb"

redis-cli -h "${host}" -p "${port}" -a "${auth_pass}" --rdb "${backup_file}" >/dev/null

sha256sum "${backup_file}" >"${backup_file}.sha256"

python3 - <<PY
import json
from pathlib import Path

out = Path("${out_dir}")
manifest = {
    "tenant_id": "${tenant_id}",
    "timestamp_utc": "${stamp}",
    "backup_file": Path("${backup_file}").name,
}
out.mkdir(parents=True, exist_ok=True)
(out / "artifact.manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
(out / "checks.json").write_text(json.dumps({"status": "backup_complete"}, indent=2, sort_keys=True) + "\n")
PY

echo "PASS dragonfly backup: ${backup_file}"
