#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"

usage() {
  cat >&2 <<'EOT'
Usage:
  doctor.sh [--live] [--tenant <id>]

Options:
  --live    Perform live connectivity checks (operator-only; guarded)
  --tenant  Optional tenant id to validate collection presence
EOT
}

mode="offline"
tenant_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live)
      mode="live"
      shift
      ;;
    --tenant)
      tenant_id="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ "${mode}" == "live" ]]; then
  require_operator_mode
  if [[ "${AI_INDEX_EXECUTE:-0}" != "1" ]]; then
    echo "ERROR: live qdrant doctor requires AI_INDEX_EXECUTE=1" >&2
    exit 1
  fi
  if [[ "${QDRANT_ENABLE:-0}" != "1" ]]; then
    echo "ERROR: live qdrant doctor requires QDRANT_ENABLE=1" >&2
    exit 1
  fi
else
  require_ci_mode
fi

read -r base_url platform_collection tenant_prefix isolation_mode < <(
QDRANT_FILE="${FABRIC_REPO_ROOT}/contracts/ai/qdrant.yml" python3 - <<'PY'
import os
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for Qdrant config: {exc}")

path = Path(os.environ["QDRANT_FILE"])
config = yaml.safe_load(path.read_text(encoding="utf-8"))
iso = config.get("tenant_isolation", {})
print(
    f"{config.get('base_url', '')}\t"
    f"{iso.get('platform_collection', '')}\t"
    f"{iso.get('tenant_prefix', '')}\t"
    f"{iso.get('mode', '')}"
)
PY
)

base_url="${base_url%/}"
if [[ -z "${base_url}" ]]; then
  echo "ERROR: qdrant base_url is empty" >&2
  exit 1
fi
if [[ ! "${base_url}" =~ ^https?://(192\.168\.|10\.) ]]; then
  echo "ERROR: qdrant base_url must be internal (got ${base_url})" >&2
  exit 1
fi
if [[ "${isolation_mode}" != "collection-per-tenant" ]]; then
  echo "ERROR: qdrant tenant isolation must be collection-per-tenant" >&2
  exit 1
fi
if [[ "${platform_collection}" != "kb_platform" ]]; then
  echo "ERROR: qdrant platform_collection must be kb_platform" >&2
  exit 1
fi
if [[ "${tenant_prefix}" != "kb_tenant_" ]]; then
  echo "ERROR: qdrant tenant_prefix must be kb_tenant_" >&2
  exit 1
fi

if [[ "${mode}" != "live" ]]; then
  echo "OK: Qdrant doctor offline (config only)"
  echo "- base_url: ${base_url}"
  echo "- platform_collection: ${platform_collection}"
  echo "- tenant_prefix: ${tenant_prefix}"
  exit 0
fi

collections_json="$(curl -sS --fail "${base_url}/collections")"
MISSING="$(COLLECTIONS_JSON="${collections_json}" PLATFORM_COLLECTION="${platform_collection}" \
TENANT_PREFIX="${tenant_prefix}" TENANT_ID="${tenant_id}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["COLLECTIONS_JSON"])
collections = [c.get("name") for c in payload.get("result", {}).get("collections", [])]
platform = os.environ["PLATFORM_COLLECTION"]
tenant_prefix = os.environ["TENANT_PREFIX"]
tenant_id = os.environ.get("TENANT_ID", "")

missing = []
if platform not in collections:
    missing.append(platform)
if tenant_id:
    tenant_collection = f"{tenant_prefix}{tenant_id}"
    if tenant_collection not in collections:
        missing.append(tenant_collection)

print("\n".join(missing))
PY
)"

if [[ -n "${MISSING}" ]]; then
  echo "ERROR: missing qdrant collections:" >&2
  echo "${MISSING}" >&2
  echo "Remediation: run guarded live indexing to create collections." >&2
  exit 1
fi

echo "OK: Qdrant reachable and collections present"
