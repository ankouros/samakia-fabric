#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

indexing_file="${FABRIC_REPO_ROOT}/contracts/ai/indexing.yml"
indexing_schema="${FABRIC_REPO_ROOT}/contracts/ai/indexing.schema.json"
qdrant_file="${FABRIC_REPO_ROOT}/contracts/ai/qdrant.yml"
qdrant_schema="${FABRIC_REPO_ROOT}/contracts/ai/qdrant.schema.json"

usage() {
  cat >&2 <<'EOT'
Usage:
  indexer.sh doctor
  indexer.sh preview --tenant <id> --source <docs|contracts|runbooks|evidence>
  indexer.sh index --tenant <id> --source <docs|contracts|runbooks|evidence> [--offline|--live]
EOT
}

validate_contracts() {
  INDEXING_FILE="${indexing_file}" INDEXING_SCHEMA="${indexing_schema}" \
  QDRANT_FILE="${qdrant_file}" QDRANT_SCHEMA="${qdrant_schema}" python3 - <<'PY'
import json
import os

try:
    import yaml
    import jsonschema
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for validation: {exc}")

indexing_file = os.environ["INDEXING_FILE"]
indexing_schema = os.environ["INDEXING_SCHEMA"]
qdrant_file = os.environ["QDRANT_FILE"]
qdrant_schema = os.environ["QDRANT_SCHEMA"]

with open(indexing_schema, "r", encoding="utf-8") as handle:
    indexing_schema_data = json.load(handle)
with open(qdrant_schema, "r", encoding="utf-8") as handle:
    qdrant_schema_data = json.load(handle)

with open(indexing_file, "r", encoding="utf-8") as handle:
    indexing_payload = yaml.safe_load(handle)
with open(qdrant_file, "r", encoding="utf-8") as handle:
    qdrant_payload = yaml.safe_load(handle)

jsonschema.validate(instance=indexing_payload, schema=indexing_schema_data)
jsonschema.validate(instance=qdrant_payload, schema=qdrant_schema_data)

print(f"PASS indexing schema: {indexing_file}")
print(f"PASS qdrant schema: {qdrant_file}")
PY
}

command="${1:-}"
shift || true

source_type=""
tenant_id=""
mode="offline"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)
      tenant_id="$2"
      shift 2
      ;;
    --source)
      source_type="$2"
      shift 2
      ;;
    --offline)
      mode="offline"
      shift
      ;;
    --live)
      mode="live"
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

if [[ "${command}" != "doctor" && "${command}" != "preview" && "${command}" != "index" ]]; then
  usage
  exit 2
fi

validate_contracts

if [[ "${command}" == "doctor" ]]; then
  INDEXING_FILE="${indexing_file}" QDRANT_FILE="${qdrant_file}" python3 - <<'PY'
import os

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for summary: {exc}")

indexing = yaml.safe_load(open(os.environ["INDEXING_FILE"], "r", encoding="utf-8"))
qdrant = yaml.safe_load(open(os.environ["QDRANT_FILE"], "r", encoding="utf-8"))

print("AI indexing configuration summary")
print(f"embedding.model: {indexing['embedding']['model']}")
print(f"chunking.chunk_size: {indexing['chunking']['chunk_size']}")
print(f"chunking.overlap: {indexing['chunking']['overlap']}")
print(f"chunking.max_chars: {indexing['chunking']['max_chars']}")
print(f"sources: {', '.join(indexing['sources'])}")
print(f"qdrant.base_url: {qdrant['base_url']}")
print(f"tenant_isolation: {qdrant['tenant_isolation']['mode']}")
PY
  exit 0
fi

if [[ -z "${tenant_id}" || -z "${source_type}" ]]; then
  usage
  exit 2
fi

if ! INDEXING_FILE="${indexing_file}" SOURCE_TYPE="${source_type}" python3 - <<'PY'
import os
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for source validation: {exc}")

indexing_file = Path(os.environ["INDEXING_FILE"])
source_type = os.environ["SOURCE_TYPE"]
payload = yaml.safe_load(indexing_file.read_text(encoding="utf-8"))
sources = payload.get("sources", [])
if source_type not in sources:
    raise SystemExit(f"ERROR: source {source_type} not allowed in indexing contract")
PY
then
  exit 1
fi

if [[ "${mode}" == "live" ]]; then
  if [[ "${command}" == "preview" ]]; then
    echo "ERROR: preview mode is offline-only" >&2
    exit 1
  fi
  if [[ "${CI:-0}" == "1" ]]; then
    echo "ERROR: live indexing is blocked in CI" >&2
    exit 1
  fi
  if [[ "${AI_INDEX_EXECUTE:-0}" != "1" ]]; then
    echo "ERROR: live indexing requires AI_INDEX_EXECUTE=1" >&2
    exit 1
  fi
  if [[ -z "${AI_INDEX_REASON:-}" ]]; then
    echo "ERROR: live indexing requires AI_INDEX_REASON" >&2
    exit 1
  fi
  if [[ "${QDRANT_ENABLE:-0}" != "1" ]]; then
    echo "ERROR: live indexing requires QDRANT_ENABLE=1" >&2
    exit 1
  fi
  if [[ "${OLLAMA_ENABLE:-0}" != "1" ]]; then
    echo "ERROR: live indexing requires OLLAMA_ENABLE=1" >&2
    exit 1
  fi
fi

source_script="${FABRIC_REPO_ROOT}/ops/ai/indexer/sources/${source_type}.sh"
if [[ ! -x "${source_script}" ]]; then
  echo "ERROR: source not supported: ${source_type}" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

source_list="${work_dir}/sources.txt"
INDEX_MODE="${mode}" bash "${source_script}" >"${source_list}"

if [[ ! -s "${source_list}" ]]; then
  echo "ERROR: no sources found for ${source_type}" >&2
  exit 1
fi

timestamp_dir="$(date -u +%Y%m%dT%H%M%SZ)"
timestamp_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

evidence_dir=""
if [[ "${command}" == "index" ]]; then
  evidence_dir="${FABRIC_REPO_ROOT}/evidence/ai/indexing/${tenant_id}/${timestamp_dir}"
  mkdir -p "${evidence_dir}/inputs"
fi

COMMAND="${command}" MODE="${mode}" TENANT_ID="${tenant_id}" SOURCE_TYPE="${source_type}" STAMP="${timestamp_utc}" \
INDEXING_FILE="${indexing_file}" QDRANT_FILE="${qdrant_file}" REPO_ROOT="${FABRIC_REPO_ROOT}" \
SOURCE_LIST="${source_list}" WORK_DIR="${work_dir}" EVIDENCE_DIR="${evidence_dir}" \
PROVIDER_FILE="${FABRIC_REPO_ROOT}/contracts/ai/provider.yml" \
QDRANT_FILE_PATH="${qdrant_file}" \
python3 - <<'PY'
import base64
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for indexing: {exc}")

command = os.environ["COMMAND"]
mode = os.environ["MODE"]
tenant_id = os.environ["TENANT_ID"]
source_type = os.environ["SOURCE_TYPE"]
indexing_file = Path(os.environ["INDEXING_FILE"])
qdrant_file = Path(os.environ["QDRANT_FILE"])
repo_root = Path(os.environ["REPO_ROOT"])
source_list = Path(os.environ["SOURCE_LIST"])
work_dir = Path(os.environ["WORK_DIR"])
evidence_dir = Path(os.environ.get("EVIDENCE_DIR", "")) if os.environ.get("EVIDENCE_DIR") else None
provider_file = os.environ.get("PROVIDER_FILE", "")
qdrant_file_path = os.environ.get("QDRANT_FILE_PATH", "")

indexing = yaml.safe_load(indexing_file.read_text(encoding="utf-8"))
qdrant = yaml.safe_load(qdrant_file.read_text(encoding="utf-8"))

chunk_size = int(indexing["chunking"]["chunk_size"])
overlap = int(indexing["chunking"]["overlap"])
max_chars = int(indexing["chunking"]["max_chars"])
embedding_model = indexing["embedding"]["model"]

exclusions = indexing.get("exclusions", {}).get("patterns", [])
redaction_patterns = indexing.get("redaction", {}).get("deny_patterns", [])

patterns_file = work_dir / "deny-patterns.txt"
patterns_file.write_text("\n".join(redaction_patterns) + "\n", encoding="utf-8")

sources = []
chunk_plan = []
redactions = []
points = []
embedding_modes = set()

def is_excluded(path_str):
    for pattern in exclusions:
        if re.search(pattern, path_str):
            return pattern
    return None

commit_sha = "unknown"
try:
    commit_sha = subprocess.check_output(["git", "-C", str(repo_root), "rev-parse", "HEAD"], text=True).strip()
except Exception:
    pass

timestamp = os.environ.get("STAMP") or os.environ.get("TIMESTAMP") or "unknown"

def relative_path(path: Path) -> str:
    try:
        return str(path.relative_to(repo_root))
    except Exception:
        return str(path)

for line in source_list.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    path = Path(line.strip())
    if not path.exists():
        continue

    path_str = str(path)
    excluded_by = is_excluded(path_str)

    content = path.read_bytes()
    content_sha = hashlib.sha256(content).hexdigest()
    size_bytes = len(content)

    source_entry = {
        "source_type": source_type,
        "source_path": relative_path(path),
        "content_sha256": content_sha,
        "size_bytes": size_bytes,
        "excluded": bool(excluded_by),
        "excluded_by": excluded_by,
    }

    if excluded_by:
        sources.append(source_entry)
        continue

    redaction_report = work_dir / "redaction.json"
    sanitized_path = work_dir / "sanitized.txt"

    redact_cmd = [
        "bash",
        str(repo_root / "ops/ai/indexer/lib/redact.sh"),
        "--file",
        str(path),
        "--patterns",
        str(patterns_file),
        "--out",
        str(sanitized_path),
        "--report",
        str(redaction_report),
    ]
    result = subprocess.run(redact_cmd)
    if result.returncode == 2:
        report = json.loads(redaction_report.read_text(encoding="utf-8"))
        redactions.append(report)
        source_entry["denied"] = True
        sources.append(source_entry)
        continue
    if result.returncode != 0:
        raise SystemExit(f"ERROR: redaction failed for {path}")

    source_entry["denied"] = False
    sources.append(source_entry)

    chunk_file = work_dir / "chunk.json"
    chunk_cmd = [
        "bash",
        str(repo_root / "ops/ai/indexer/lib/chunk.sh"),
        "--file",
        str(sanitized_path),
        "--max-chars",
        str(chunk_size),
        "--overlap",
        str(overlap),
        "--out",
        str(chunk_file),
    ]
    subprocess.check_call(chunk_cmd)
    chunk_payload = json.loads(chunk_file.read_text(encoding="utf-8"))

    for chunk in chunk_payload.get("chunks", []):
        start = chunk["start"]
        end = chunk["end"]
        text = chunk["text"]
        if len(text) > max_chars:
            text = text[:max_chars]

        chunk_id = hashlib.sha256(
            f"{source_entry['source_path']}:{start}:{end}:{content_sha}".encode("utf-8")
        ).hexdigest()

        chunk_plan.append({
            "chunk_id": chunk_id,
            "source_path": source_entry["source_path"],
            "start": start,
            "end": end,
            "content_sha256": content_sha,
        })

        if command == "preview":
            continue

        temp_text = work_dir / "chunk.txt"
        temp_text.write_text(text, encoding="utf-8")

        env = os.environ.copy()
        env["INDEX_MODE"] = mode
        env["OLLAMA_ENABLE"] = env.get("OLLAMA_ENABLE", "0")
        env["PROVIDER_FILE"] = provider_file

        embed_cmd = [
            "bash",
            str(repo_root / "ops/ai/indexer/lib/ollama.sh"),
            "--text-file",
            str(temp_text),
            "--model",
            embedding_model,
        ]
        embed_result = subprocess.run(embed_cmd, env=env, capture_output=True, text=True)
        if embed_result.returncode != 0:
            raise SystemExit(f"ERROR: embedding failed for {source_entry['source_path']}")
        embed_payload = json.loads(embed_result.stdout)
        embedding_modes.add(embed_payload.get("embedding_mode", "unknown"))

        points.append({
            "id": chunk_id,
            "vector": embed_payload.get("embedding"),
            "payload": {
                "tenant_id": tenant_id,
                "env": os.environ.get("ENV", "unknown"),
                "source_type": source_type,
                "source_path": source_entry["source_path"],
                "commit_sha": commit_sha,
                "timestamp_utc": timestamp,
                "content_sha256": content_sha,
                "chunk_start": start,
                "chunk_end": end,
            },
        })

if command == "preview":
    chunk_plan_sorted = sorted(chunk_plan, key=lambda item: item["chunk_id"])
    print(json.dumps({"chunks": chunk_plan_sorted}, indent=2, sort_keys=True))
    raise SystemExit(0)

if evidence_dir is None:
    raise SystemExit("ERROR: evidence dir missing")

evidence_dir.mkdir(parents=True, exist_ok=True)
(evidence_dir / "inputs").mkdir(parents=True, exist_ok=True)

(evidence_dir / "inputs/README.md").write_text(
    "Inputs are listed in sources.json. Raw content is not stored.\n",
    encoding="utf-8",
)

(evidence_dir / "indexing.yml").write_text(indexing_file.read_text(encoding="utf-8"), encoding="utf-8")
(evidence_dir / "qdrant.yml").write_text(qdrant_file.read_text(encoding="utf-8"), encoding="utf-8")

sources_sorted = sorted(sources, key=lambda item: item["source_path"])
chunk_plan_sorted = sorted(chunk_plan, key=lambda item: item["chunk_id"])

(evidence_dir / "sources.json").write_text(
    json.dumps({"sources": sources_sorted}, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

(evidence_dir / "chunk-plan.json").write_text(
    json.dumps({"chunks": chunk_plan_sorted}, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

(evidence_dir / "redaction.json").write_text(
    json.dumps({"redactions": redactions}, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

embedding_mode = "mixed" if len(embedding_modes) > 1 else (next(iter(embedding_modes), "stub"))
(evidence_dir / "embedding.json").write_text(
    json.dumps({
        "model": embedding_model,
        "embedding_mode": embedding_mode,
        "points": len(points),
    }, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

collection = qdrant["tenant_isolation"]["platform_collection"] if tenant_id == "platform" else f"{qdrant['tenant_isolation']['tenant_prefix']}{tenant_id}"

qdrant_mode = "live" if mode == "live" else "dry-run"
vector_size = len(points[0]["vector"]) if points else 0

(evidence_dir / "qdrant.json").write_text(
    json.dumps({
        "collection": collection,
        "mode": qdrant_mode,
        "vector_size": vector_size,
        "points": len(points),
    }, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

summary = [
    "# AI Indexing Summary",
    "",
    f"Tenant: {tenant_id}",
    f"Source: {source_type}",
    f"Mode: {mode}",
    f"Indexed files: {len([s for s in sources if not s.get('excluded') and not s.get('denied')])}",
    f"Denied files: {len([s for s in sources if s.get('denied')])}",
    f"Excluded files: {len([s for s in sources if s.get('excluded')])}",
    f"Chunks: {len(chunk_plan)}",
    f"Points: {len(points)}",
    f"Embedding mode: {embedding_mode}",
]
(evidence_dir / "summary.md").write_text("\n".join(summary) + "\n", encoding="utf-8")

if mode == "live" and points:
    points_file = work_dir / "points.json"
    points_file.write_text(json.dumps({"points": points}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    env = os.environ.copy()
    env["QDRANT_ENABLE"] = env.get("QDRANT_ENABLE", "0")
    env["QDRANT_FILE"] = qdrant_file_path
    subprocess.check_call([
        "bash",
        str(repo_root / "ops/ai/indexer/lib/qdrant.sh"),
        "create",
        "--collection",
        collection,
        "--vector-size",
        str(vector_size),
    ], env=env)
    subprocess.check_call([
        "bash",
        str(repo_root / "ops/ai/indexer/lib/qdrant.sh"),
        "upsert",
        "--collection",
        collection,
        "--points",
        str(points_file),
    ], env=env)
PY

if [[ "${command}" == "index" ]]; then
  bash "${FABRIC_REPO_ROOT}/ops/ai/indexer/lib/manifest.sh" --dir "${evidence_dir}" --out "${evidence_dir}/manifest.sha256"
  if [[ "${EVIDENCE_SIGN:-0}" == "1" ]]; then
    if [[ -z "${EVIDENCE_GPG_KEY:-}" ]]; then
      echo "ERROR: EVIDENCE_SIGN=1 but EVIDENCE_GPG_KEY is not set" >&2
      exit 1
    fi
    if ! command -v gpg >/dev/null 2>&1; then
      echo "ERROR: gpg not found; cannot sign evidence" >&2
      exit 1
    fi
    gpg --batch --yes --local-user "${EVIDENCE_GPG_KEY}" \
      --armor --detach-sign "${evidence_dir}/manifest.sha256"
  fi
  echo "OK: indexing evidence written to ${evidence_dir}"
fi
