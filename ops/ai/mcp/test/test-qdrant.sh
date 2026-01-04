#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${FABRIC_REPO_ROOT:-}" ]]; then
  FABRIC_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  export FABRIC_REPO_ROOT
fi

export RUNNER_MODE=ci

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/ai/mcp/test/common.sh"

log_dir="$(mcp_log_dir)"
port=18785
pid="$(mcp_start_server "qdrant" "${port}" "${FABRIC_REPO_ROOT}/ops/ai/mcp/qdrant/server.sh" "${log_dir}")"

cleanup() {
  mcp_stop_server "${pid}"
  rm -rf "${log_dir}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

before_audit="$(mcp_audit_count)"

response="$(mcp_post "http://127.0.0.1:${port}/query" \
  '{"action":"search","params":{"vector":[0.1,0.2,0.3],"top_k":2}}' tenant canary)"
assert_json_ok "qdrant search" "${response}"
assert_json_field "qdrant fixture" "data.source" "fixture" "${response}"

response="$(mcp_post "http://127.0.0.1:${port}/query" \
  '{"action":"search","params":{"vector":[]}}' tenant canary)"
assert_json_error "qdrant vector missing" "vector_required" "${response}"

assert_audit_written "${before_audit}" 2

echo "PASS: qdrant MCP"
