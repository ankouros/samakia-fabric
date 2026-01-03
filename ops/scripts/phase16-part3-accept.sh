#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker_part3="${acceptance_dir}/PHASE16_PART3_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase16.part3] ${label}"
  "$@"
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Operator docs check" make -C "${FABRIC_REPO_ROOT}" docs.operator.check
run_step "AI MCP doctor" make -C "${FABRIC_REPO_ROOT}" ai.mcp.doctor
run_step "Phase 16 Part 3 entry check" make -C "${FABRIC_REPO_ROOT}" phase16.part3.entry.check

repo_port=8781
evidence_port=8782
obs_port=8783
runbooks_port=8784
qdrant_port=8785

pids=()
log_dir="${FABRIC_REPO_ROOT}/tmp/ai-mcp"
mkdir -p "${log_dir}"

start_server() {
  local name="$1"
  local port="$2"
  local script="$3"
  MCP_TEST_MODE=1 MCP_PORT="${port}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" \
    bash "${script}" >"${log_dir}/${name}.log" 2>&1 &
  pids+=("$!")
  for _ in {1..30}; do
    if curl -sS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
      return
    fi
    sleep 0.2
  done
  echo "ERROR: ${name} MCP failed to start on port ${port}" >&2
  exit 1
}

cleanup() {
  for pid in "${pids[@]}"; do
    kill "${pid}" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

start_server "repo" "${repo_port}" "${FABRIC_REPO_ROOT}/ops/ai/mcp/repo/server.sh"
start_server "evidence" "${evidence_port}" "${FABRIC_REPO_ROOT}/ops/ai/mcp/evidence/server.sh"
start_server "observability" "${obs_port}" "${FABRIC_REPO_ROOT}/ops/ai/mcp/observability/server.sh"
start_server "runbooks" "${runbooks_port}" "${FABRIC_REPO_ROOT}/ops/ai/mcp/runbooks/server.sh"
start_server "qdrant" "${qdrant_port}" "${FABRIC_REPO_ROOT}/ops/ai/mcp/qdrant/server.sh"

request_and_check() {
  local label="$1"
  local url="$2"
  local payload="$3"
  local identity="$4"
  local tenant="$5"
  local expect_ok="$6"
  local out
  out="$(mktemp)"
  if ! curl -sS -H "X-MCP-Identity: ${identity}" -H "X-MCP-Tenant: ${tenant}" \
    -H "Content-Type: application/json" -d "${payload}" "${url}" >"${out}"; then
    echo "ERROR: ${label} request failed" >&2
    cat "${out}" >&2 || true
    rm -f "${out}"
    exit 1
  fi

  if ! EXPECT_OK="${expect_ok}" RESPONSE_PATH="${out}" python3 - <<'PY'
import json
import os
from pathlib import Path

expect_ok = os.environ.get("EXPECT_OK") == "1"
payload = json.loads(Path(os.environ["RESPONSE_PATH"]).read_text(encoding="utf-8"))
if bool(payload.get("ok")) is not expect_ok:
    raise SystemExit(1)
PY
  then
    echo "ERROR: ${label} response did not match expectation" >&2
    cat "${out}" >&2 || true
    rm -f "${out}"
    exit 1
  fi
  rm -f "${out}"
}

request_ok() {
  local label="$1"
  local url="$2"
  local payload="$3"
  request_and_check "${label}" "${url}" "${payload}" "operator" "platform" "1"
}

request_not_ok() {
  local label="$1"
  local url="$2"
  local payload="$3"
  local identity="$4"
  local tenant="$5"
  request_and_check "${label}" "${url}" "${payload}" "${identity}" "${tenant}" "0"
}

request_ok "repo list files" "http://127.0.0.1:${repo_port}/query" '{"action":"list_files"}'
request_ok "repo read file" "http://127.0.0.1:${repo_port}/query" '{"action":"read_file","params":{"path":"docs/ai/overview.md"}}'

mkdir -p "${FABRIC_REPO_ROOT}/evidence/ai/indexing/platform"
mkdir -p "${FABRIC_REPO_ROOT}/evidence/ai/indexing/canary"
echo "{" >"${FABRIC_REPO_ROOT}/evidence/ai/indexing/platform/sample.json"
echo "}" >>"${FABRIC_REPO_ROOT}/evidence/ai/indexing/platform/sample.json"
echo "{" >"${FABRIC_REPO_ROOT}/evidence/ai/indexing/canary/sample.json"
echo "}" >>"${FABRIC_REPO_ROOT}/evidence/ai/indexing/canary/sample.json"

request_not_ok "evidence tenant isolation" "http://127.0.0.1:${evidence_port}/query" \
  '{"action":"read_file","params":{"path":"evidence/ai/indexing/platform/sample.json"}}' "tenant" "canary"

request_and_check "evidence tenant ok" "http://127.0.0.1:${evidence_port}/query" \
  '{"action":"read_file","params":{"path":"evidence/ai/indexing/canary/sample.json"}}' "tenant" "canary" "1"

request_ok "observability prometheus" "http://127.0.0.1:${obs_port}/query" \
  '{"action":"query_prometheus","params":{"query_name":"infra_cpu","start":0,"end":60,"step":60}}'
request_ok "observability loki" "http://127.0.0.1:${obs_port}/query" \
  '{"action":"query_loki","params":{"query_name":"syslog_errors","start":0,"end":60,"limit":10}}'

request_ok "runbooks list" "http://127.0.0.1:${runbooks_port}/query" '{"action":"list_runbooks"}'
request_ok "runbooks read" "http://127.0.0.1:${runbooks_port}/query" \
  '{"action":"read_runbook","params":{"path":"docs/operator/ai.md"}}'

request_ok "qdrant search" "http://127.0.0.1:${qdrant_port}/query" \
  '{"action":"search","params":{"vector":[0.1,0.2,0.3],"top_k":3}}'

mcp_audit_root="${FABRIC_REPO_ROOT}/evidence/ai/mcp-audit"
if [[ ! -d "${mcp_audit_root}" ]]; then
  echo "ERROR: MCP audit root missing: ${mcp_audit_root}" >&2
  exit 1
fi

latest_audit_dir="$(find "${mcp_audit_root}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort | tail -n1)"
if [[ -z "${latest_audit_dir}" ]]; then
  echo "ERROR: MCP audit directory missing" >&2
  exit 1
fi

for file in request.json decision.json response.meta.json manifest.sha256; do
  if [[ ! -f "${mcp_audit_root}/${latest_audit_dir}/${file}" ]]; then
    echo "ERROR: audit file missing: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$(${commit_hash_script})"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker_part3}" <<EOF_MARKER
# Phase 16 Part 3 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- make ai.mcp.doctor
- make phase16.part3.entry.check

Result: PASS

Audit evidence:
- ${mcp_audit_root}/${latest_audit_dir}

Statement:
MCP services are read-only; no execution or mutation possible.
EOF_MARKER

self_hash_part3="$(sha256sum "${marker_part3}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_part3}"
} >>"${marker_part3}"
sha256sum "${marker_part3}" | awk '{print $1}' >"${marker_part3}.sha256"
