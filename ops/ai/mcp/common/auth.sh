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


mcp_identity_header="X-MCP-Identity"
mcp_tenant_header="X-MCP-Tenant"
mcp_request_id_header="X-MCP-Request-Id"

export_mcp_auth_headers() {
  export MCP_IDENTITY_HEADER="${mcp_identity_header}"
  export MCP_TENANT_HEADER="${mcp_tenant_header}"
  export MCP_REQUEST_ID_HEADER="${mcp_request_id_header}"
}
