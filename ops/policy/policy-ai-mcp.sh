#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


mcp_root="${FABRIC_REPO_ROOT}/ops/ai/mcp"

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

kinds=(repo evidence observability runbooks qdrant)

for kind in "${kinds[@]}"; do
  require_file "${mcp_root}/${kind}/allowlist.yml"
  require_exec "${mcp_root}/${kind}/server.sh"
  require_exec "${mcp_root}/${kind}/handlers.sh"

  "${mcp_root}/${kind}/server.sh" doctor

  actions_json="$(bash -c "source '${mcp_root}/${kind}/handlers.sh'; mcp_routes_json")"

  ACTIONS_JSON="${actions_json}" python3 - <<'PY'
import json
import os

raw = os.environ.get("ACTIONS_JSON", "")
try:
    payload = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit("ERROR: handlers.sh did not emit valid JSON")

actions = payload.get("actions", [])
if not actions:
    raise SystemExit("ERROR: handlers.sh must list actions")

forbidden = ["write", "delete", "upsert", "apply", "exec", "mutate"]
for action in actions:
    if any(word in action for word in forbidden):
        raise SystemExit(f"ERROR: forbidden action detected: {action}")

print("PASS: MCP actions are read-only")
PY

done

if rg -n "shell=True" "${mcp_root}" >/dev/null 2>&1; then
  echo "ERROR: MCP server must not use shell=True" >&2
  exit 1
fi

if ! rg -n "MCP_TEST_MODE" "${mcp_root}/common/server.py" >/dev/null 2>&1; then
  echo "ERROR: MCP server missing test-mode guard" >&2
  exit 1
fi

if ! rg -n "OBS_LIVE" "${mcp_root}/common/server.py" >/dev/null 2>&1; then
  echo "ERROR: MCP server missing OBS_LIVE guard" >&2
  exit 1
fi

if ! rg -n "QDRANT_LIVE" "${mcp_root}/common/server.py" >/dev/null 2>&1; then
  echo "ERROR: MCP server missing QDRANT_LIVE guard" >&2
  exit 1
fi

echo "OK: AI MCP policy checks passed"
