#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

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

indexer_script="${FABRIC_REPO_ROOT}/ops/ai/indexer/indexer.sh"
ollama_script="${FABRIC_REPO_ROOT}/ops/ai/indexer/lib/ollama.sh"
qdrant_script="${FABRIC_REPO_ROOT}/ops/ai/indexer/lib/qdrant.sh"
redact_script="${FABRIC_REPO_ROOT}/ops/ai/indexer/lib/redact.sh"
chunk_script="${FABRIC_REPO_ROOT}/ops/ai/indexer/lib/chunk.sh"

indexing_file="${FABRIC_REPO_ROOT}/contracts/ai/indexing.yml"
provider_file="${FABRIC_REPO_ROOT}/contracts/ai/provider.yml"
qdrant_file="${FABRIC_REPO_ROOT}/contracts/ai/qdrant.yml"

require_exec "${indexer_script}"
require_exec "${ollama_script}"
require_exec "${qdrant_script}"
require_exec "${redact_script}"
require_exec "${chunk_script}"

require_file "${indexing_file}"
require_file "${provider_file}"
require_file "${qdrant_file}"

INDEXING_FILE="${indexing_file}" PROVIDER_FILE="${provider_file}" QDRANT_FILE="${qdrant_file}" python3 - <<'PY'
import os
import re

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for live indexing policy: {exc}")

indexing = yaml.safe_load(open(os.environ["INDEXING_FILE"], "r", encoding="utf-8"))
provider = yaml.safe_load(open(os.environ["PROVIDER_FILE"], "r", encoding="utf-8"))
qdrant = yaml.safe_load(open(os.environ["QDRANT_FILE"], "r", encoding="utf-8"))

embedding = indexing.get("embedding", {})
if embedding.get("provider") != "ollama":
    raise SystemExit("ERROR: embedding provider must be ollama")
if embedding.get("model") != "nomic-embed-text":
    raise SystemExit("ERROR: embedding model must be nomic-embed-text")

provider_url = provider.get("base_url")
if provider_url != "http://192.168.11.30:11434":
    raise SystemExit("ERROR: Ollama base_url must be http://192.168.11.30:11434")

base_url = qdrant.get("base_url", "")
if not re.match(r"^https?://(192\.168\.|10\.)", base_url):
    raise SystemExit(f"ERROR: qdrant base_url must be internal (got {base_url})")

patterns = indexing.get("redaction", {}).get("deny_patterns", [])
required = ["password", "token", "TEST_ONLY_SECRET"]
missing = [item for item in required if not any(item in p for p in patterns)]
if not any("PRIVATE" in p and "KEY" in p for p in patterns):
    missing.append("PRIVATE_KEY_PATTERN")
if missing:
    raise SystemExit(f"ERROR: redaction patterns missing: {', '.join(missing)}")

print("PASS: AI live indexing contract checks")
PY

if ! rg -n "require_operator_mode" "${indexer_script}" >/dev/null 2>&1; then
  echo "ERROR: indexer must enforce operator mode for live runs" >&2
  exit 1
fi

if ! rg -n "redaction deny patterns matched" "${indexer_script}" >/dev/null 2>&1; then
  echo "ERROR: indexer must hard-fail on redaction deny patterns" >&2
  exit 1
fi

if ! rg -n "192\.168\.11\.30:11434" "${ollama_script}" >/dev/null 2>&1; then
  echo "ERROR: ollama script must enforce the internal base_url" >&2
  exit 1
fi

if ! rg -n "qdrant base_url must be internal" "${qdrant_script}" >/dev/null 2>&1; then
  echo "ERROR: qdrant script must enforce internal base_url" >&2
  exit 1
fi

if ! rg -n "live indexing is blocked in CI" "${indexer_script}" >/dev/null 2>&1; then
  echo "ERROR: indexer must block live indexing in CI" >&2
  exit 1
fi

echo "OK: AI live indexing policy checks passed"
