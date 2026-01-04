#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


mcp_root="${FABRIC_REPO_ROOT}/ops/ai/mcp"
common_root="${mcp_root}/common"
deploy_root="${mcp_root}/deploy"
test_root="${mcp_root}/test"

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

require_file "${common_root}/server.py"
require_exec "${common_root}/http.sh"

require_file "${deploy_root}/README.md"
require_file "${deploy_root}/env.example"
require_file "${deploy_root}/systemd/mcp-repo.service"
require_file "${deploy_root}/systemd/mcp-evidence.service"
require_file "${deploy_root}/systemd/mcp-observability.service"
require_file "${deploy_root}/systemd/mcp-runbooks.service"
require_file "${deploy_root}/systemd/mcp-qdrant.service"

require_exec "${mcp_root}/start.sh"
require_exec "${mcp_root}/stop.sh"
require_exec "${test_root}/run.sh"
require_exec "${test_root}/test-repo.sh"
require_exec "${test_root}/test-evidence.sh"
require_exec "${test_root}/test-observability.sh"
require_exec "${test_root}/test-runbooks.sh"
require_exec "${test_root}/test-qdrant.sh"

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

if ! rg -n "RUNNER_MODE" "${mcp_root}/common/server.py" >/dev/null 2>&1; then
  echo "ERROR: MCP server missing runner-mode guard" >&2
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

if ! rg -n "write_audit" "${mcp_root}/common/server.py" >/dev/null 2>&1; then
  echo "ERROR: MCP server missing audit logging" >&2
  exit 1
fi

echo "OK: AI MCP policy checks passed"
