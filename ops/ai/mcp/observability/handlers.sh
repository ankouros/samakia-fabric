#!/usr/bin/env bash
set -euo pipefail

mcp_routes_json() {
  cat <<'JSON'
{
  "actions": ["query_prometheus", "query_loki"]
}
JSON
}
