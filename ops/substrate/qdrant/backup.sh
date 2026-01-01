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

require_command curl

local_json="$(cat "${entry}")"
host=$(jq -r '.endpoints.host' <<<"${local_json}")
port=$(jq -r '.endpoints.port' <<<"${local_json}")
protocol=$(jq -r '.endpoints.protocol' <<<"${local_json}")
secret_ref=$(jq -r '.secret_ref' <<<"${local_json}")
resources=$(jq -c '.resources' <<<"${local_json}")

collection=$(python3 - <<PY
import json
print(json.loads('''${resources}''').get('collection', '') or '')
PY
)

if [[ -z "${collection}" ]]; then
  echo "ERROR: resources.collection is required for qdrant backup" >&2
  exit 2
fi

secret_json=$(load_secret_json "${secret_ref}")
api_key=$(get_secret_field "${secret_json}" "api_key")
if [[ -z "${api_key}" ]]; then
  api_key=$(get_secret_field "${secret_json}" "token")
fi

if [[ -z "${api_key}" ]]; then
  echo "ERROR: API key missing in secret_ref ${secret_ref}" >&2
  exit 2
fi

mkdir -p "${out_dir}"
base_url="${protocol}://${host}:${port}"
backup_file="${out_dir}/snapshot.json"

curl -sf -H "Authorization: Bearer ${api_key}" -H "content-type: application/json" \
  -X POST "${base_url}/collections/${collection}/snapshots" -d '{}' >"${backup_file}"

sha256sum "${backup_file}" >"${backup_file}.sha256"

python3 - <<PY
import json
from pathlib import Path

out = Path("${out_dir}")
manifest = {
    "tenant_id": "${tenant_id}",
    "timestamp_utc": "${stamp}",
    "collection": "${collection}",
    "backup_file": Path("${backup_file}").name,
}
out.mkdir(parents=True, exist_ok=True)
(out / "artifact.manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
(out / "checks.json").write_text(json.dumps({"status": "backup_complete"}, indent=2, sort_keys=True) + "\n")
PY

echo "PASS qdrant backup: ${backup_file}"
