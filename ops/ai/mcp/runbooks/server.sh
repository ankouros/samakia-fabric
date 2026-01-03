#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
common_dir="${script_dir}/../common"

# shellcheck disable=SC1091
source "${common_dir}/errors.sh"
# shellcheck disable=SC1091
source "${common_dir}/auth.sh"
# shellcheck disable=SC1091
source "${common_dir}/allowlist.sh"
# shellcheck disable=SC1091
source "${script_dir}/handlers.sh"

export_mcp_auth_headers

export MCP_KIND="runbooks"
export MCP_REPO_ROOT="${FABRIC_REPO_ROOT}"
export MCP_ALLOWLIST="${script_dir}/allowlist.yml"
export MCP_ROUTES_JSON
MCP_ROUTES_JSON="$(mcp_routes_json)"

if [[ "${1:-}" == "doctor" ]]; then
  MCP_ALLOWLIST_KIND="runbooks" validate_allowlist "${MCP_ALLOWLIST}"
  echo "OK: runbooks MCP config"
  exit 0
fi

export MCP_PORT="${MCP_PORT:-8784}"
exec python3 "${common_dir}/server.py"
