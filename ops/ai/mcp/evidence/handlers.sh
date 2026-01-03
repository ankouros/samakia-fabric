#!/usr/bin/env bash
set -euo pipefail

mcp_routes_json() {
  cat <<'JSON'
{
  "actions": ["list_evidence", "read_file"]
}
JSON
}
