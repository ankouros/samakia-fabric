#!/usr/bin/env bash
set -euo pipefail

mcp_routes_json() {
  cat <<'JSON'
{
  "actions": ["list_runbooks", "read_runbook"]
}
JSON
}
