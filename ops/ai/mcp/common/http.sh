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

mcp_request_id() {
  date -u +%Y%m%dT%H%M%SZ
}

mcp_post() {
  local url="$1"
  local payload="$2"
  local identity="$3"
  local tenant="$4"
  local request_id="${5:-$(mcp_request_id)}"

  curl -sS \
    -H "Content-Type: application/json" \
    -H "X-MCP-Identity: ${identity}" \
    -H "X-MCP-Tenant: ${tenant}" \
    -H "X-MCP-Request-Id: ${request_id}" \
    -d "${payload}" \
    "${url}"
}

mcp_health() {
  local url="$1"
  curl -sS "${url}/healthz"
}
