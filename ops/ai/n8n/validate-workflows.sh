#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

workflow_dir="${FABRIC_REPO_ROOT}/ops/ai/n8n/workflows"
if [[ ! -d "${workflow_dir}" ]]; then
  echo "ERROR: workflows directory missing: ${workflow_dir}" >&2
  exit 1
fi

mapfile -t workflow_files < <(find "${workflow_dir}" -type f -name "*.json" -print | sort)
if [[ "${#workflow_files[@]}" -eq 0 ]]; then
  echo "ERROR: no workflows found in ${workflow_dir}" >&2
  exit 1
fi

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
evidence_dir="${FABRIC_REPO_ROOT}/evidence/ai/n8n/${stamp}"
mkdir -p "${evidence_dir}"

workflows_json="${evidence_dir}/workflows.json"
validation_json="${evidence_dir}/validation.json"

status=0
if ! WORKFLOW_FILES="$(printf '%s\n' "${workflow_files[@]}")" \
  PROVIDER_FILE="${FABRIC_REPO_ROOT}/contracts/ai/provider.yml" \
  QDRANT_FILE="${FABRIC_REPO_ROOT}/contracts/ai/qdrant.yml" \
  WORKFLOWS_JSON_OUT="${workflows_json}" \
  VALIDATION_JSON_OUT="${validation_json}" \
  python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for n8n validation: {exc}")

workflow_files = [Path(p) for p in os.environ["WORKFLOW_FILES"].splitlines() if p]
provider_file = Path(os.environ["PROVIDER_FILE"])
qdrant_file = Path(os.environ["QDRANT_FILE"])
workflows_out = Path(os.environ["WORKFLOWS_JSON_OUT"])
validation_out = Path(os.environ["VALIDATION_JSON_OUT"])

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

results = []
errors = []


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
    name = data.get("name", path.name)
    nodes = data.get("nodes", [])
    node_errors = []

    if data.get("active") is not False:
        node_errors.append("workflow must be inactive (active=false)")

    for node in nodes:
        node_type = node.get("type")
        if node_type not in allowed_nodes:
            node_errors.append(f"node type not allowed: {node_type}")
        credentials = node.get("credentials")
        if credentials:
            node_errors.append("credentials must not be embedded in workflow JSON")

    http_hits = []
    for value in iter_strings(data):
        if "http://" in value or "https://" in value:
            if not any(value.startswith(url) for url in allowed_urls):
                http_hits.append(value)

    if http_hits:
        node_errors.append("external endpoints not allowed")

    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    results.append({
        "path": str(path),
        "name": name,
        "sha256": digest,
        "nodes": len(nodes),
        "errors": node_errors,
    })

    if node_errors:
        errors.append({"path": str(path), "errors": node_errors})

workflows_out.write_text(
    json.dumps({"workflows": results}, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

validation_out.write_text(
    json.dumps({"status": "fail" if errors else "pass", "errors": errors}, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

if errors:
    raise SystemExit("ERROR: n8n workflow validation failed")
PY
then
  status=$?
fi

INDEX_MODE="offline" bash "${FABRIC_REPO_ROOT}/ops/ai/indexer/lib/manifest.sh" \
  --dir "${evidence_dir}" --out "${evidence_dir}/manifest.sha256"

if [[ "${status}" -ne 0 ]]; then
  exit "${status}"
fi

echo "OK: n8n workflow validation evidence written to ${evidence_dir}"
