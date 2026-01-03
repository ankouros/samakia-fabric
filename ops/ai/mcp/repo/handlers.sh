#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


mcp_routes_json() {
  cat <<'JSON'
{
  "actions": ["list_files", "read_file", "git_diff", "git_log"]
}
JSON
}
