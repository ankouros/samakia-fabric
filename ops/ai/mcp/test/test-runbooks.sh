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
port=18784
pid="$(mcp_start_server "runbooks" "${port}" "${FABRIC_REPO_ROOT}/ops/ai/mcp/runbooks/server.sh" "${log_dir}")"

cleanup() {
  mcp_stop_server "${pid}"
  rm -rf "${log_dir}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

before_audit="$(mcp_audit_count)"

response="$(mcp_post "http://127.0.0.1:${port}/query" \
  '{"action":"list_runbooks","params":{}}' tenant canary)"
assert_json_ok "runbooks list" "${response}"

response="$(mcp_post "http://127.0.0.1:${port}/query" \
  '{"action":"read_runbook","params":{"path":"docs/operator/ai.md"}}' tenant canary)"
assert_json_ok "runbooks read" "${response}"

response="$(mcp_post "http://127.0.0.1:${port}/query" \
  '{"action":"read_runbook","params":{"path":"README.md"}}' tenant canary)"
assert_json_error "runbooks read denied" "path_not_allowed" "${response}"

assert_audit_written "${before_audit}" 3

echo "PASS: runbooks MCP"
