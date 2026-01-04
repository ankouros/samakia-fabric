#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_operator_mode

if ! command -v systemctl >/dev/null 2>&1; then
  echo "ERROR: systemctl not found" >&2
  exit 1
fi

systemctl_cmd=(systemctl)
if [[ "${MCP_SYSTEMD_SCOPE:-}" == "user" ]]; then
  systemctl_cmd=(systemctl --user)
fi

services=(mcp-repo mcp-evidence mcp-observability mcp-runbooks mcp-qdrant)
if [[ -n "${MCP_SERVICES:-}" ]]; then
  read -r -a services <<<"${MCP_SERVICES}"
fi

for service in "${services[@]}"; do
  "${systemctl_cmd[@]}" start "${service}.service"
  echo "OK: started ${service}.service"
done
