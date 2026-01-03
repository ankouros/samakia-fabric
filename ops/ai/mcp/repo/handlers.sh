#!/usr/bin/env bash
set -euo pipefail

mcp_routes_json() {
  cat <<'JSON'
{
  "actions": ["list_files", "read_file", "git_diff", "git_log"]
}
JSON
}
