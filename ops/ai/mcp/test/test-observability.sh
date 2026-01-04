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
port=18783
pid="$(mcp_start_server "observability" "${port}" "${FABRIC_REPO_ROOT}/ops/ai/mcp/observability/server.sh" "${log_dir}")"

cleanup() {
  mcp_stop_server "${pid}"
  rm -rf "${log_dir}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

before_audit="$(mcp_audit_count)"

response="$(mcp_post "http://127.0.0.1:${port}/query" \
  '{"action":"query_prometheus","params":{"query_name":"infra_cpu","start":0,"end":300,"step":60}}' tenant canary)"
assert_json_ok "observability query_prometheus" "${response}"
assert_json_field "observability fixture" "data.source" "fixture" "${response}"

response="$(mcp_post "http://127.0.0.1:${port}/query" \
  '{"action":"query_prometheus","params":{"query_name":"unknown","start":0,"end":300,"step":60}}' tenant canary)"
assert_json_error "observability query denied" "query_not_allowed" "${response}"

assert_audit_written "${before_audit}" 2

echo "PASS: observability MCP"
