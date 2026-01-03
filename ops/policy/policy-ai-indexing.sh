#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: required file missing: ${path}" >&2
    exit 1
  fi
}

require_exec() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: required executable missing: ${path}" >&2
    exit 1
  fi
}

indexing_file="${FABRIC_REPO_ROOT}/contracts/ai/indexing.yml"
indexing_schema="${FABRIC_REPO_ROOT}/contracts/ai/indexing.schema.json"
indexer_script="${FABRIC_REPO_ROOT}/ops/ai/indexer/indexer.sh"

require_file "${indexing_file}"
require_file "${indexing_schema}"
require_exec "${indexer_script}"

INDEXING_FILE="${indexing_file}" INDEXING_SCHEMA="${indexing_schema}" python3 - <<'PY'
import json
import os

try:
    import yaml
    import jsonschema
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for indexing policy: {exc}")

indexing_file = os.environ["INDEXING_FILE"]
indexing_schema = os.environ["INDEXING_SCHEMA"]

with open(indexing_schema, "r", encoding="utf-8") as handle:
    schema = json.load(handle)
with open(indexing_file, "r", encoding="utf-8") as handle:
    payload = yaml.safe_load(handle)

jsonschema.validate(instance=payload, schema=schema)

embed = payload.get("embedding", {})
if embed.get("provider") != "ollama" or embed.get("model") != "nomic-embed-text":
    raise SystemExit("ERROR: embeddings must use ollama + nomic-embed-text")

patterns = payload.get("redaction", {}).get("deny_patterns", [])
required = ["password", "token", "TEST_ONLY_SECRET"]
missing = [item for item in required if not any(item in p for p in patterns)]
if not any("PRIVATE" in p and "KEY" in p for p in patterns):
    missing.append("PRIVATE_KEY_PATTERN")
if missing:
    raise SystemExit(f"ERROR: redaction patterns missing: {', '.join(missing)}")

print("PASS: AI indexing contract enforced")
PY

if ! rg -n "AI_INDEX_EXECUTE" "${indexer_script}" >/dev/null 2>&1; then
  echo "ERROR: indexer missing AI_INDEX_EXECUTE guard" >&2
  exit 1
fi

if ! rg -n "AI_INDEX_REASON" "${indexer_script}" >/dev/null 2>&1; then
  echo "ERROR: indexer missing AI_INDEX_REASON guard" >&2
  exit 1
fi

if ! rg -n "QDRANT_ENABLE" "${indexer_script}" >/dev/null 2>&1; then
  echo "ERROR: indexer missing QDRANT_ENABLE guard" >&2
  exit 1
fi

if ! rg -n "OLLAMA_ENABLE" "${indexer_script}" >/dev/null 2>&1; then
  echo "ERROR: indexer missing OLLAMA_ENABLE guard" >&2
  exit 1
fi

if ! rg -n "live indexing is blocked in CI" "${indexer_script}" >/dev/null 2>&1; then
  echo "ERROR: indexer missing CI guard for live mode" >&2
  exit 1
fi

echo "OK: AI indexing policy checks passed"
