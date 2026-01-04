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
source "${FABRIC_REPO_ROOT}/ops/ai/mcp/common/http.sh"

mcp_audit_root() {
  echo "${FABRIC_REPO_ROOT}/evidence/ai/mcp-audit"
}

mcp_audit_count() {
  local root
  root="$(mcp_audit_root)"
  if [[ ! -d "${root}" ]]; then
    echo 0
    return
  fi
  find "${root}" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '
}

mcp_latest_audit_dir() {
  local root
  root="$(mcp_audit_root)"
  if [[ ! -d "${root}" ]]; then
    echo ""
    return
  fi
  find "${root}" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
    | sort -nr | head -n1 | awk '{print $2}'
}

mcp_log_dir() {
  mktemp -d "/tmp/samakia-mcp-test.XXXXXX"
}

mcp_start_server() {
  local name="$1"
  local port="$2"
  local script="$3"
  local log_dir="$4"

  MCP_TEST_MODE=1 RUNNER_MODE=ci FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" MCP_PORT="${port}" \
    bash "${script}" >"${log_dir}/${name}.log" 2>&1 &
  local pid=$!
  for _ in {1..30}; do
    if curl -sS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
      echo "${pid}"
      return
    fi
    sleep 0.2
  done
  echo "ERROR: ${name} MCP failed to start on port ${port}" >&2
  kill "${pid}" >/dev/null 2>&1 || true
  exit 1
}

mcp_stop_server() {
  local pid="$1"
  kill "${pid}" >/dev/null 2>&1 || true
}

assert_json_ok() {
  local label="$1"
  local response="$2"

  if ! MCP_RESPONSE="${response}" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ["MCP_RESPONSE"])
if not payload.get("ok"):
    raise SystemExit(1)
print("ok")
PY
  then
    echo "ERROR: ${label} did not return ok" >&2
    echo "Response: ${response}" >&2
    exit 1
  fi
}

assert_json_error() {
  local label="$1"
  local expected="$2"
  local response="$3"

  if ! MCP_RESPONSE="${response}" python3 - <<PY
import json
import os
payload = json.loads(os.environ["MCP_RESPONSE"])
if payload.get("error") != "${expected}":
    raise SystemExit(1)
print("ok")
PY
  then
    echo "ERROR: ${label} did not return error=${expected}" >&2
    echo "Response: ${response}" >&2
    exit 1
  fi
}

assert_json_field() {
  local label="$1"
  local field="$2"
  local expected="$3"
  local response="$4"

  if ! MCP_RESPONSE="${response}" python3 - <<PY
import json
import os
payload = json.loads(os.environ["MCP_RESPONSE"])
value = payload
for part in "${field}".split("."):
    value = value.get(part, None) if isinstance(value, dict) else None
if value != "${expected}":
    raise SystemExit(1)
print("ok")
PY
  then
    echo "ERROR: ${label} did not return ${field}=${expected}" >&2
    echo "Response: ${response}" >&2
    exit 1
  fi
}

assert_audit_written() {
  local before="$1"
  local expected_delta="$2"

  local after
  after="$(mcp_audit_count)"
  if [[ "${after}" -lt $((before + expected_delta)) ]]; then
    echo "ERROR: audit logs missing (before=${before}, after=${after})" >&2
    exit 1
  fi

  local latest
  latest="$(mcp_latest_audit_dir)"
  if [[ -z "${latest}" ]]; then
    echo "ERROR: audit directory not found" >&2
    exit 1
  fi

  for file in request.json decision.json response.meta.json manifest.sha256; do
    if [[ ! -f "${latest}/${file}" ]]; then
      echo "ERROR: missing audit file ${latest}/${file}" >&2
      exit 1
    fi
  done
}
