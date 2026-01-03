#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ops_root="${FABRIC_REPO_ROOT}/ops/ai"
evidence_root="${FABRIC_REPO_ROOT}/evidence/ai"

usage() {
  cat <<'EOT'
Samakia Fabric AI Ops (analysis-only)

Usage:
  ops.sh doctor
  ops.sh index.preview TENANT=<platform|tenant> SOURCE=<docs|contracts|runbooks|evidence>
  ops.sh index.offline TENANT=<platform|tenant> SOURCE=<docs|contracts|runbooks|evidence>
  ops.sh analyze.plan FILE=<analysis.yml>
  ops.sh analyze.run FILE=<analysis.yml> (guarded)
  ops.sh status
EOT
}

fail() {
  local message="$1"
  local hint="${2:-}"
  echo "ERROR: ${message}" >&2
  if [[ -n "${hint}" ]]; then
    echo "Next steps: ${hint}" >&2
  fi
  exit 1
}

require_env() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "${value}" ]]; then
    fail "Missing required env: ${name}" "Run: ${0} --help"
  fi
}

require_operator() {
  local runner_mode="${RUNNER_MODE:-ci}"
  if [[ "${CI:-}" == "1" || "${runner_mode}" == "ci" ]]; then
    fail "AI execution is blocked in CI mode" "Set RUNNER_MODE=operator and re-run"
  fi
}

policy_routing_mcp() {
  bash "${FABRIC_REPO_ROOT}/ops/policy/policy-ai-routing.sh"
  bash "${FABRIC_REPO_ROOT}/ops/policy/policy-ai-mcp.sh"
}

policy_indexing() {
  bash "${FABRIC_REPO_ROOT}/ops/policy/policy-ai-indexing.sh"
}

command="${1:-}"
shift || true

case "${command}" in
  doctor)
    bash "${ops_root}/ai.sh" doctor
    bash "${ops_root}/indexer/indexer.sh" doctor
    bash "${ops_root}/mcp/doctor.sh"
    if [[ -x "${ops_root}/evidence/validate-index.sh" ]]; then
      bash "${ops_root}/evidence/validate-index.sh"
    fi
    ;;
  index.preview)
    require_env TENANT
    require_env SOURCE
    policy_indexing
    make -C "${FABRIC_REPO_ROOT}" ai.index.preview TENANT="${TENANT}" SOURCE="${SOURCE}"
    ;;
  index.offline)
    require_env TENANT
    require_env SOURCE
    policy_indexing
    make -C "${FABRIC_REPO_ROOT}" ai.index.offline TENANT="${TENANT}" SOURCE="${SOURCE}"
    ;;
  analyze.plan)
    require_env FILE
    policy_routing_mcp
    make -C "${FABRIC_REPO_ROOT}" ai.analyze.plan FILE="${FILE}"
    ;;
  analyze.run)
    require_env FILE
    require_operator
    if [[ "${AI_ANALYZE_EXECUTE:-0}" != "1" ]]; then
      fail "AI_ANALYZE_EXECUTE=1 required for analyze.run" "Set AI_ANALYZE_EXECUTE=1 and re-run"
    fi
    policy_routing_mcp
    make -C "${FABRIC_REPO_ROOT}" ai.analyze.run FILE="${FILE}" AI_ANALYZE_EXECUTE=1
    ;;
  status)
    index_json="${evidence_root}/index.json"
    if [[ ! -f "${index_json}" ]]; then
      echo "AI evidence index: missing (${index_json})"
      echo "Next steps: bash ${ops_root}/evidence/rebuild-index.sh"
      exit 0
    fi
    python3 - "${index_json}" <<'PY'
import json
import sys

path = sys.argv[1]
payload = json.load(open(path, "r", encoding="utf-8"))
counts = payload.get("counts", {})
print(f"AI evidence index: {path}")
print(f"Generated UTC: {payload.get('generated_utc')}")
print(f"Operator: {payload.get('operator')}")
print(f"Total entries: {len(payload.get('entries', []))}")
for key in sorted(counts):
    print(f"- {key}: {counts[key]}")
PY
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    fail "Unknown command: ${command}" "Run: ${0} --help"
    ;;
esac
