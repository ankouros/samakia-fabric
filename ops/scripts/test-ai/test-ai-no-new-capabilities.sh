#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


schema_path="${FABRIC_REPO_ROOT}/contracts/ai/analysis.schema.json"

python3 - "${schema_path}" <<'PY'
import json
import sys

schema_path = sys.argv[1]
schema = json.load(open(schema_path, "r", encoding="utf-8"))
expected = {
    "drift_explain",
    "slo_explain",
    "incident_summary",
    "plan_review",
    "change_impact",
    "compliance_summary",
}
found = set(schema.get("properties", {}).get("analysis_type", {}).get("enum", []))
if found != expected:
    raise SystemExit(f"ERROR: analysis types changed: {sorted(found)}")
print("PASS: analysis types locked")
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
import sys

actions_payload = json.loads(os.environ["ACTIONS_JSON"])
expected_payload = json.loads(os.environ["EXPECTED_JSON"])
actions = sorted(actions_payload.get("actions", []))
expected = sorted(expected_payload)
if actions != expected:
    raise SystemExit(f"ERROR: MCP actions changed: {actions} != {expected}")
PY
done

echo "PASS: MCP action sets locked"
