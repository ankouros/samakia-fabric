#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


SCHEMA_PATH="${FABRIC_REPO_ROOT}/contracts/ai/analysis.schema.json" \
PROVIDER_PATH="${FABRIC_REPO_ROOT}/contracts/ai/provider.yml" \
INDEXING_PATH="${FABRIC_REPO_ROOT}/contracts/ai/indexing.yml" \
python3 - <<'PY'
import json
import os

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for AI contract test: {exc}")

schema_path = os.environ["SCHEMA_PATH"]
provider_path = os.environ["PROVIDER_PATH"]
indexing_path = os.environ["INDEXING_PATH"]

schema = json.load(open(schema_path, "r", encoding="utf-8"))
expected_types = {
    "drift_explain",
    "slo_explain",
    "incident_summary",
    "plan_review",
    "change_impact",
    "compliance_summary",
}
found_types = set(schema.get("properties", {}).get("analysis_type", {}).get("enum", []))
if found_types != expected_types:
    raise SystemExit("ERROR: analysis types changed")

provider = yaml.safe_load(open(provider_path, "r", encoding="utf-8"))
if provider.get("provider") != "ollama":
    raise SystemExit("ERROR: provider is not ollama")
if provider.get("allow_external_providers") is not False:
    raise SystemExit("ERROR: allow_external_providers must be false")
if provider.get("mode") != "analysis-only":
    raise SystemExit("ERROR: provider mode must be analysis-only")

indexing = yaml.safe_load(open(indexing_path, "r", encoding="utf-8"))
expected_sources = {"docs", "contracts", "runbooks", "evidence"}
found_sources = set(indexing.get("sources", []) or [])
if found_sources != expected_sources:
    raise SystemExit("ERROR: indexing sources changed")

print("PASS: AI contract invariants locked")
PY

MCP_ROOT="${FABRIC_REPO_ROOT}/ops/ai/mcp" EXPECTED_SERVICES="repo,evidence,observability,runbooks,qdrant" python3 - <<'PY'
import os

mcp_root = os.environ["MCP_ROOT"]
expected = set(os.environ["EXPECTED_SERVICES"].split(","))
found = set()

for root, _, files in os.walk(mcp_root):
    if "handlers.sh" in files:
        found.add(os.path.basename(root))

if found != expected:
    raise SystemExit(f"ERROR: MCP services changed: {sorted(found)}")

print("PASS: MCP service list locked")
PY

declare -A expected_actions
expected_actions["repo"]='["list_files","read_file","git_diff","git_log"]'
expected_actions["evidence"]='["list_evidence","read_file"]'
expected_actions["observability"]='["query_prometheus","query_loki"]'
expected_actions["runbooks"]='["list_runbooks","read_runbook"]'
expected_actions["qdrant"]='["search"]'

for name in "${!expected_actions[@]}"; do
  handler="${FABRIC_REPO_ROOT}/ops/ai/mcp/${name}/handlers.sh"
  if [[ ! -f "${handler}" ]]; then
    echo "ERROR: missing MCP handler: ${handler}" >&2
    exit 1
  fi
  actions="$(bash -lc "source '${handler}'; mcp_routes_json")"
  ACTIONS_JSON="${actions}" EXPECTED_JSON="${expected_actions[${name}]}" python3 - <<'PY'
import json
import os

actions_payload = json.loads(os.environ["ACTIONS_JSON"])
expected_payload = json.loads(os.environ["EXPECTED_JSON"])
found = sorted(actions_payload.get("actions", []))
expected = sorted(expected_payload)
if found != expected:
    raise SystemExit(f"ERROR: MCP actions changed: {found} != {expected}")
PY

done

echo "PASS: MCP action sets locked"
