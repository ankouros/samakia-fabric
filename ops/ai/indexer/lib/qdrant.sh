#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOT'
Usage:
  qdrant.sh create --collection <name> --vector-size <n> [--dry-run]
  qdrant.sh upsert --collection <name> --points <file> [--dry-run]
  qdrant.sh search --collection <name> --vector <file> --limit <n> [--dry-run]
EOT
}

command="${1:-}"
shift || true

collection=""
vector_size=""
points_file=""
vector_file=""
limit="5"
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --collection)
      collection="$2"
      shift 2
      ;;
    --vector-size)
      vector_size="$2"
      shift 2
      ;;
    --points)
      points_file="$2"
      shift 2
      ;;
    --vector)
      vector_file="$2"
      shift 2
      ;;
    --limit)
      limit="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
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

if [[ -z "${command}" ]]; then
  usage
  exit 2
fi

validate_collection() {
  local name="$1"
  if [[ "${name}" == "kb_platform" ]]; then
    return 0
  fi
  if [[ "${name}" == kb_tenant_* ]]; then
    return 0
  fi
  echo "ERROR: invalid collection name: ${name}" >&2
  exit 1
}

base_url="${QDRANT_BASE_URL:-}"
if [[ -z "${base_url}" ]]; then
  base_url="$(QDRANT_FILE="${QDRANT_FILE:-}" python3 - <<'PY'
import os
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for Qdrant config: {exc}")

qdrant_path = os.environ.get("QDRANT_FILE") or "contracts/ai/qdrant.yml"
path = Path(qdrant_path)
if not path.exists():
    raise SystemExit(f"ERROR: qdrant contract not found: {qdrant_path}")
config = yaml.safe_load(path.read_text(encoding="utf-8"))
print(config.get("base_url", ""))
PY
)"
fi

if [[ "${QDRANT_ENABLE:-0}" != "1" ]]; then
  dry_run=1
fi

case "${command}" in
  create)
    if [[ -z "${collection}" || -z "${vector_size}" ]]; then
      usage
      exit 2
    fi
    validate_collection "${collection}"
    if [[ "${dry_run}" -eq 1 ]]; then
      echo "DRY-RUN: create collection ${collection} (size=${vector_size})"
      exit 0
    fi
    curl -sS --fail -X PUT "${base_url}/collections/${collection}" \
      -H 'Content-Type: application/json' \
      -d "$(VECTOR_SIZE="${vector_size}" python3 - <<'PY'
import json
import os

vector_size = int(os.environ["VECTOR_SIZE"])
print(json.dumps({"vectors": {"size": vector_size, "distance": "Cosine"}}))
PY
)" >/dev/null
    ;;
  upsert)
    if [[ -z "${collection}" || -z "${points_file}" ]]; then
      usage
      exit 2
    fi
    validate_collection "${collection}"
    if [[ ! -f "${points_file}" ]]; then
      echo "ERROR: points file not found: ${points_file}" >&2
      exit 1
    fi
    if [[ "${dry_run}" -eq 1 ]]; then
      echo "DRY-RUN: upsert points into ${collection} from ${points_file}"
      exit 0
    fi
    curl -sS --fail -X PUT "${base_url}/collections/${collection}/points?wait=true" \
      -H 'Content-Type: application/json' \
      -d "$(cat "${points_file}")" >/dev/null
    ;;
  search)
    if [[ -z "${collection}" || -z "${vector_file}" ]]; then
      usage
      exit 2
    fi
    validate_collection "${collection}"
    if [[ ! -f "${vector_file}" ]]; then
      echo "ERROR: vector file not found: ${vector_file}" >&2
      exit 1
    fi
    if [[ "${dry_run}" -eq 1 ]]; then
      echo "DRY-RUN: search ${collection} using ${vector_file}" >&2
      exit 0
    fi
    curl -sS --fail -X POST "${base_url}/collections/${collection}/points/search" \
      -H 'Content-Type: application/json' \
      -d "$(VECTOR_FILE="${vector_file}" LIMIT="${limit}" python3 - <<'PY'
import json
import os
from pathlib import Path

vector = json.loads(Path(os.environ["VECTOR_FILE"]).read_text())
limit = int(os.environ.get("LIMIT", "5"))
print(json.dumps({"vector": vector, "limit": limit}))
PY
)" >/dev/null
    ;;
  *)
    usage
    exit 2
    ;;
esac
