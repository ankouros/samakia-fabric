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
port=18781
pid="$(mcp_start_server "repo" "${port}" "${FABRIC_REPO_ROOT}/ops/ai/mcp/repo/server.sh" "${log_dir}")"

cleanup() {
  mcp_stop_server "${pid}"
  rm -rf "${log_dir}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

before_audit="$(mcp_audit_count)"

response="$(mcp_post "http://127.0.0.1:${port}/query" \
  '{"action":"list_files","params":{"path":"docs"}}' tenant canary)"
assert_json_ok "repo list_files" "${response}"

response="$(mcp_post "http://127.0.0.1:${port}/query" \
  '{"action":"read_file","params":{"path":"docs/README.md"}}' tenant canary)"
assert_json_ok "repo read_file" "${response}"

response="$(mcp_post "http://127.0.0.1:${port}/query" \
  '{"action":"read_file","params":{"path":"README.md"}}' tenant canary)"
assert_json_error "repo read_file denied" "path_not_allowed" "${response}"

assert_audit_written "${before_audit}" 3

echo "PASS: repo MCP"
