#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

workflow_dir="${FABRIC_REPO_ROOT}/ops/ai/n8n/workflows"
readme_file="${FABRIC_REPO_ROOT}/ops/ai/n8n/README.md"
validate_script="${FABRIC_REPO_ROOT}/ops/ai/n8n/validate-workflows.sh"

if [[ ! -d "${workflow_dir}" ]]; then
  echo "ERROR: n8n workflows directory missing: ${workflow_dir}" >&2
  exit 1
fi
if [[ ! -f "${readme_file}" ]]; then
  echo "ERROR: n8n README missing: ${readme_file}" >&2
  exit 1
fi
if [[ ! -x "${validate_script}" ]]; then
  echo "ERROR: n8n validate script missing or not executable: ${validate_script}" >&2
  exit 1
fi

mapfile -t workflow_files < <(find "${workflow_dir}" -type f -name "*.json" -print | sort)
if [[ "${#workflow_files[@]}" -eq 0 ]]; then
  echo "ERROR: no workflows found in ${workflow_dir}" >&2
  exit 1
fi

WORKFLOW_FILES="$(printf '%s\n' "${workflow_files[@]}")" \
PROVIDER_FILE="${FABRIC_REPO_ROOT}/contracts/ai/provider.yml" \
QDRANT_FILE="${FABRIC_REPO_ROOT}/contracts/ai/qdrant.yml" \
python3 - <<'PY'
import json
import os
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for n8n policy: {exc}")

workflow_files = [Path(p) for p in os.environ["WORKFLOW_FILES"].splitlines() if p]
provider_file = Path(os.environ["PROVIDER_FILE"])
qdrant_file = Path(os.environ["QDRANT_FILE"])

provider = yaml.safe_load(provider_file.read_text(encoding="utf-8"))
qdrant = yaml.safe_load(qdrant_file.read_text(encoding="utf-8"))

allowed_urls = [
    (provider.get("base_url") or "").rstrip("/"),
    (qdrant.get("base_url") or "").rstrip("/"),
]
allowed_urls = [u for u in allowed_urls if u]

allowed_nodes = {
    "n8n-nodes-base.cron",
    "n8n-nodes-base.manualTrigger",
    "n8n-nodes-base.readBinaryFile",
    "n8n-nodes-base.readBinaryFiles",
    "n8n-nodes-base.set",
    "n8n-nodes-base.writeBinaryFile",
}


def iter_strings(obj):
    if isinstance(obj, dict):
        for value in obj.values():
            yield from iter_strings(value)
    elif isinstance(obj, list):
        for item in obj:
            yield from iter_strings(item)
    elif isinstance(obj, str):
        yield obj


for path in workflow_files:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("active") is not False:
        raise SystemExit(f"ERROR: workflow must be inactive: {path}")

    for node in data.get("nodes", []):
        node_type = node.get("type")
        if node_type not in allowed_nodes:
            raise SystemExit(f"ERROR: disallowed node type {node_type} in {path}")
        if node.get("credentials"):
            raise SystemExit(f"ERROR: credentials must not be embedded in {path}")

    for value in iter_strings(data):
        if "http://" in value or "https://" in value:
            if not any(value.startswith(url) for url in allowed_urls):
                raise SystemExit(f"ERROR: external endpoint not allowed in {path}: {value}")

print("PASS: n8n workflow policy checks")
PY

echo "OK: AI n8n policy checks passed"
