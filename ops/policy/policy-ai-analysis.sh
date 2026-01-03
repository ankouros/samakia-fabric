#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: required file missing: ${path}" >&2
    exit 1
  fi
}

require_exec() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: required executable missing: ${path}" >&2
    exit 1
  fi
}

analysis_file="${FABRIC_REPO_ROOT}/contracts/ai/analysis.yml"
analysis_schema="${FABRIC_REPO_ROOT}/contracts/ai/analysis.schema.json"
analysis_script="${FABRIC_REPO_ROOT}/ops/ai/analysis/analyze.sh"
assemble_script="${FABRIC_REPO_ROOT}/ops/ai/analysis/assemble-context.sh"
call_script="${FABRIC_REPO_ROOT}/ops/ai/analysis/call-ollama.sh"
redact_script="${FABRIC_REPO_ROOT}/ops/ai/analysis/redact.sh"
prompts_dir="${FABRIC_REPO_ROOT}/ops/ai/analysis/prompts"

require_file "${analysis_file}"
require_file "${analysis_schema}"
require_exec "${analysis_script}"
require_exec "${assemble_script}"
require_exec "${call_script}"
require_exec "${redact_script}"

ANALYSIS_FILE="${analysis_file}" ANALYSIS_SCHEMA="${analysis_schema}" python3 - <<'PY'
import json
import os

try:
    import yaml
    import jsonschema
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for analysis policy: {exc}")

analysis_file = os.environ["ANALYSIS_FILE"]
analysis_schema = os.environ["ANALYSIS_SCHEMA"]

with open(analysis_schema, "r", encoding="utf-8") as handle:
    schema = json.load(handle)
with open(analysis_file, "r", encoding="utf-8") as handle:
    payload = yaml.safe_load(handle)

jsonschema.validate(instance=payload, schema=schema)

print("PASS: AI analysis contract enforced")
PY

if ! rg -n "AI_ANALYZE_EXECUTE" "${analysis_script}" >/dev/null 2>&1; then
  echo "ERROR: analyze.sh missing AI_ANALYZE_EXECUTE guard" >&2
  exit 1
fi

if ! rg -n "blocked in CI" "${analysis_script}" >/dev/null 2>&1; then
  echo "ERROR: analyze.sh missing CI guard" >&2
  exit 1
fi

if ! rg -n "AI_ANALYZE_EXECUTE" "${call_script}" >/dev/null 2>&1; then
  echo "ERROR: call-ollama.sh missing AI_ANALYZE_EXECUTE guard" >&2
  exit 1
fi

if ! rg -n "blocked in CI" "${call_script}" >/dev/null 2>&1; then
  echo "ERROR: call-ollama.sh missing CI guard" >&2
  exit 1
fi

if ! rg -n "AI_ANALYZE_MAX_EVIDENCE_ITEMS" "${assemble_script}" >/dev/null 2>&1; then
  echo "ERROR: assemble-context.sh missing max evidence guard" >&2
  exit 1
fi

if ! rg -n "AI_ANALYZE_MAX_ITEM_CHARS" "${assemble_script}" >/dev/null 2>&1; then
  echo "ERROR: assemble-context.sh missing max item guard" >&2
  exit 1
fi

if ! rg -n "AI_ANALYZE_MAX_TOTAL_CHARS" "${assemble_script}" >/dev/null 2>&1; then
  echo "ERROR: assemble-context.sh missing max total guard" >&2
  exit 1
fi

for prompt in "${prompts_dir}"/*.md; do
  if ! rg -n "Do not suggest actions or remediation" "${prompt}" >/dev/null 2>&1; then
    echo "ERROR: prompt missing no-action guard: ${prompt}" >&2
    exit 1
  fi
  if ! rg -n "Do not invent facts" "${prompt}" >/dev/null 2>&1; then
    echo "ERROR: prompt missing no-hallucination guard: ${prompt}" >&2
    exit 1
  fi
  if ! rg -n "Only reason from the evidence provided" "${prompt}" >/dev/null 2>&1; then
    echo "ERROR: prompt missing evidence-only guard: ${prompt}" >&2
    exit 1
  fi
done

if ! rg -n "REDACTED_TENANT" "${redact_script}" >/dev/null 2>&1; then
  echo "ERROR: redact.sh missing tenant redaction" >&2
  exit 1
fi

echo "OK: AI analysis policy checks passed"
