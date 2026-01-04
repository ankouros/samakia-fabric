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
port=18782
pid="$(mcp_start_server "evidence" "${port}" "${FABRIC_REPO_ROOT}/ops/ai/mcp/evidence/server.sh" "${log_dir}")"

tenant_dir="${FABRIC_REPO_ROOT}/evidence/tenants/canary/mcp-test"
mkdir -p "${tenant_dir}"
fixture_path="${tenant_dir}/sample.txt"
echo "ok" >"${fixture_path}"

cleanup() {
  mcp_stop_server "${pid}"
  rm -rf "${tenant_dir}" >/dev/null 2>&1 || true
  rm -rf "${log_dir}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

before_audit="$(mcp_audit_count)"

response="$(mcp_post "http://127.0.0.1:${port}/query" \
  '{"action":"read_file","params":{"path":"evidence/tenants/canary/mcp-test/sample.txt"}}' tenant canary)"
assert_json_ok "evidence read_file" "${response}"

response="$(mcp_post "http://127.0.0.1:${port}/query" \
  '{"action":"read_file","params":{"path":"evidence/tenants/canary/mcp-test/sample.txt"}}' tenant other)"
assert_json_error "evidence tenant isolation" "tenant_isolation" "${response}"

assert_audit_written "${before_audit}" 2

echo "PASS: evidence MCP"
