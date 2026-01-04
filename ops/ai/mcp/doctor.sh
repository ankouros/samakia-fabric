#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"

if [[ "${RUNNER_MODE:-ci}" == "operator" ]]; then
  require_operator_mode
else
  require_ci_mode
fi


mcp_root="${FABRIC_REPO_ROOT}/ops/ai/mcp"

kinds=(repo evidence observability runbooks qdrant)
for kind in "${kinds[@]}"; do
  "${mcp_root}/${kind}/server.sh" doctor
  echo "OK: ${kind} MCP validated"
done

echo "OK: MCP doctor checks passed"
