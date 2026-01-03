#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


root="${POLICY_AI_BOUNDARY_ROOT:-${FABRIC_REPO_ROOT}}"

analysis_schema="${root}/contracts/ai/analysis.schema.json"
provider_file="${root}/contracts/ai/provider.yml"
routing_file="${root}/contracts/ai/routing.yml"
indexing_file="${root}/contracts/ai/indexing.yml"
mcp_root="${root}/ops/ai/mcp"
analysis_root="${root}/ops/ai/analysis"
ops_entry="${root}/ops/ai/ops.sh"

violations=()

record_violation() {
  violations+=("$1")
}

if [[ ! -f "${analysis_schema}" ]]; then
  record_violation "missing analysis schema"
else
  if ! python3 - "${analysis_schema}" <<'PY' >/dev/null; then
import json
import sys

schema = json.load(open(sys.argv[1], "r", encoding="utf-8"))
expected = {
    "drift_explain",
    "slo_explain",
    "incident_summary",
    "plan_review",
    "change_impact",
    "compliance_summary",
}
found = set(schema.get("properties", {}).get("analysis_type", {}).get("enum", []))
if found != expected:
    raise SystemExit(1)
PY
    record_violation "analysis types changed"
  fi
fi

if [[ ! -f "${provider_file}" ]]; then
  record_violation "missing provider contract"
else
  if ! python3 - "${provider_file}" <<'PY' >/dev/null; then
import sys
try:
    import yaml
except Exception as exc:
    raise SystemExit(exc)

provider = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
if provider.get("provider") != "ollama":
    raise SystemExit(1)
if provider.get("allow_external_providers") is not False:
    raise SystemExit(1)
if provider.get("mode") != "analysis-only":
    raise SystemExit(1)
PY
    record_violation "provider contract changed"
  fi
fi

if [[ ! -f "${routing_file}" ]]; then
  record_violation "missing routing contract"
else
  if ! python3 - "${routing_file}" <<'PY' >/dev/null; then
import sys
try:
    import yaml
except Exception as exc:
    raise SystemExit(exc)

routing = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
expected_defaults = {
    "ops": "gpt-oss:20b",
    "code": "starcoder2:15b",
    "embeddings": "nomic-embed-text",
}
expected_routes = {
    "ops.analysis": "gpt-oss:20b",
    "ops.summary": "gpt-oss:20b",
    "ops.incident": "gpt-oss:20b",
    "code.review": "starcoder2:15b",
    "code.generate": "starcoder2:15b",
    "embeddings": "nomic-embed-text",
}

if routing.get("defaults", {}) != expected_defaults:
    raise SystemExit(1)
found = {route.get("task"): route.get("model") for route in routing.get("routes", [])}
if found != expected_routes:
    raise SystemExit(1)
if len(routing.get("routes", [])) != len(expected_routes):
    raise SystemExit(1)
PY
    record_violation "routing policy changed"
  fi
fi

if [[ ! -f "${indexing_file}" ]]; then
  record_violation "missing indexing contract"
else
  if ! python3 - "${indexing_file}" <<'PY' >/dev/null; then
import sys
try:
    import yaml
except Exception as exc:
    raise SystemExit(exc)

indexing = yaml.safe_load(open(sys.argv[1], "r", encoding="utf-8"))
expected_sources = {"docs", "contracts", "runbooks", "evidence"}
found_sources = set(indexing.get("sources", []) or [])
if found_sources != expected_sources:
    raise SystemExit(1)
PY
    record_violation "indexing sources changed"
  fi
fi

if [[ -d "${mcp_root}" ]]; then
  if ! MCP_ROOT="${mcp_root}" python3 - <<'PY' >/dev/null; then
import os

mcp_root = os.environ["MCP_ROOT"]
expected = {"repo", "evidence", "observability", "runbooks", "qdrant"}
found = set()

for root, _, files in os.walk(mcp_root):
    if "handlers.sh" in files:
        found.add(os.path.basename(root))

if found != expected:
    raise SystemExit(1)
PY
    record_violation "MCP service set changed"
  fi

  declare -A expected_actions
  expected_actions["repo"]='["list_files","read_file","git_diff","git_log"]'
  expected_actions["evidence"]='["list_evidence","read_file"]'
  expected_actions["observability"]='["query_prometheus","query_loki"]'
  expected_actions["runbooks"]='["list_runbooks","read_runbook"]'
  expected_actions["qdrant"]='["search"]'

  for name in "${!expected_actions[@]}"; do
    handler="${mcp_root}/${name}/handlers.sh"
    if [[ ! -f "${handler}" ]]; then
      record_violation "missing MCP handler: ${name}"
      continue
    fi
    actions="$(bash -lc "source '${handler}'; mcp_routes_json")"
    if ! ACTIONS_JSON="${actions}" EXPECTED_JSON="${expected_actions[${name}]}" python3 - <<'PY' >/dev/null; then
import json
import os

found = sorted(json.loads(os.environ["ACTIONS_JSON"]).get("actions", []))
expected = sorted(json.loads(os.environ["EXPECTED_JSON"]))
if found != expected:
    raise SystemExit(1)
PY
      record_violation "MCP actions changed: ${name}"
    fi
  done
else
  record_violation "missing MCP directory"
fi

if [[ -d "${analysis_root}" && -f "${ops_entry}" ]]; then
  if rg -n "terraform apply|ansible-playbook|kubectl|pveam|pct|qm|safe-run|remediate\.sh|--execute" \
    "${analysis_root}" "${ops_entry}" >/dev/null 2>&1; then
    record_violation "execution tooling referenced in AI analysis"
  fi
else
  record_violation "missing AI analysis entrypoints"
fi

roadmap_ok=0
adr_ok=0
accept_ok=0

if rg -n "Phase (1[7-9]|[2-9][0-9])" "${root}/ROADMAP.md" >/dev/null 2>&1; then
  roadmap_ok=1
fi

if rg -n -i "ADR-[0-9]+.*AI.*Phase (1[7-9]|[2-9][0-9])" "${root}/DECISIONS.md" >/dev/null 2>&1; then
  adr_ok=1
fi

if compgen -G "${root}/acceptance/PHASE1[7-9]*.md" >/dev/null \
  || compgen -G "${root}/acceptance/PHASE[2-9][0-9]*.md" >/dev/null; then
  accept_ok=1
fi

phase_unlocked=0
if [[ ${roadmap_ok} -eq 1 && ${adr_ok} -eq 1 && ${accept_ok} -eq 1 ]]; then
  phase_unlocked=1
fi

if [[ ${#violations[@]} -gt 0 ]]; then
  if [[ ${phase_unlocked} -ne 1 ]]; then
    echo "ERROR: AI capability expansion detected without Phase >=17 + ADR + acceptance plan" >&2
    for reason in "${violations[@]}"; do
      echo "- ${reason}" >&2
    done
    exit 1
  fi
  echo "WARN: AI capability expansion detected, but Phase >=17 + ADR + acceptance plan present" >&2
  for reason in "${violations[@]}"; do
    echo "- ${reason}" >&2
  done
fi

echo "OK: AI phase boundary policy checks passed"
