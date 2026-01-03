#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

analysis_root="${FABRIC_REPO_ROOT}/ops/ai/analysis"
schema_path="${FABRIC_REPO_ROOT}/contracts/ai/analysis.schema.json"
routing_file="${FABRIC_REPO_ROOT}/contracts/ai/routing.yml"
provider_file="${FABRIC_REPO_ROOT}/contracts/ai/provider.yml"

usage() {
  cat >&2 <<'EOT'
Usage:
  analyze.sh plan --file <analysis.yml> [--out-dir <path>]
  analyze.sh run --file <analysis.yml> [--out-dir <path>]
  analyze.sh compare --file-a <analysis.yml> --file-b <analysis.yml>
EOT
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

read_meta() {
  local meta_path="$1"
  local key="$2"
  python3 - "${meta_path}" "${key}" <<'PY'
import json
import sys

meta_path = sys.argv[1]
key = sys.argv[2]
with open(meta_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
value = payload.get(key)
if value is None:
    raise SystemExit(f"ERROR: missing analysis field: {key}")
print(value)
PY
}

cmd="${1:-}"
shift || true

case "${cmd}" in
  plan|run)
    analysis_file=""
    out_dir=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --file)
          analysis_file="$2"
          shift 2
          ;;
        --out-dir)
          out_dir="$2"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          echo "ERROR: unknown argument: $1" >&2
          usage
          exit 2
          ;;
      esac
    done

    if [[ -z "${analysis_file}" ]]; then
      usage
      exit 2
    fi

    if [[ ! -f "${analysis_file}" ]]; then
      echo "ERROR: analysis file not found: ${analysis_file}" >&2
      exit 1
    fi

    require_cmd date
    require_cmd python3
    require_cmd sha256sum
    require_cmd curl

    if [[ ! -f "${schema_path}" ]]; then
      echo "ERROR: analysis schema missing: ${schema_path}" >&2
      exit 1
    fi

    if [[ ! -f "${routing_file}" ]]; then
      echo "ERROR: routing contract missing: ${routing_file}" >&2
      exit 1
    fi

    if [[ ! -f "${provider_file}" ]]; then
      echo "ERROR: provider contract missing: ${provider_file}" >&2
      exit 1
    fi

    analysis_meta="$(mktemp)"
    ANALYSIS_FILE="${analysis_file}" ANALYSIS_SCHEMA="${schema_path}" python3 - <<'PY' >"${analysis_meta}"
import json
import os

try:
    import yaml
    import jsonschema
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for analysis validation: {exc}")

analysis_file = os.environ["ANALYSIS_FILE"]
analysis_schema = os.environ["ANALYSIS_SCHEMA"]

with open(analysis_schema, "r", encoding="utf-8") as handle:
    schema = json.load(handle)
with open(analysis_file, "r", encoding="utf-8") as handle:
    analysis = yaml.safe_load(handle)

jsonschema.validate(instance=analysis, schema=schema)

inputs = analysis.get("inputs", {})
time_window = inputs.get("time_window", {})
meta = {
    "analysis_id": analysis.get("analysis_id"),
    "analysis_type": analysis.get("analysis_type"),
    "requester_role": analysis.get("requester_role"),
    "tenant_id": analysis.get("tenant", {}).get("id"),
    "tenant_scope": analysis.get("tenant", {}).get("scope"),
    "output_format": analysis.get("output_format"),
    "max_tokens": analysis.get("max_tokens"),
    "evidence_refs": inputs.get("evidence_refs", []),
    "time_window_start": time_window.get("start_utc"),
    "time_window_end": time_window.get("end_utc"),
}

print(json.dumps(meta, indent=2, sort_keys=True))
PY

    analysis_id="$(read_meta "${analysis_meta}" analysis_id)"
    analysis_type="$(read_meta "${analysis_meta}" analysis_type)"
    requester_role="$(read_meta "${analysis_meta}" requester_role)"
    tenant_id="$(read_meta "${analysis_meta}" tenant_id)"
    tenant_scope="$(read_meta "${analysis_meta}" tenant_scope)"
    output_format="$(read_meta "${analysis_meta}" output_format)"
    max_tokens="$(read_meta "${analysis_meta}" max_tokens)"
    time_start="$(read_meta "${analysis_meta}" time_window_start)"
    time_end="$(read_meta "${analysis_meta}" time_window_end)"

    tenant_id_display="${tenant_id}"
    if [[ "${requester_role}" != "operator" ]]; then
      tenant_id_display="redacted"
    fi

    if [[ "${AI_ANALYZE_DISABLE:-0}" == "1" ]]; then
      echo "ERROR: AI analysis is disabled by operator kill switch" >&2
      exit 1
    fi

    if [[ -n "${AI_ANALYZE_BLOCK_TYPES:-}" ]]; then
      IFS=',' read -r -a blocked_types <<<"${AI_ANALYZE_BLOCK_TYPES}"
      for blocked in "${blocked_types[@]}"; do
        if [[ "${analysis_type}" == "${blocked}" ]]; then
          echo "ERROR: analysis type blocked by operator kill switch: ${analysis_type}" >&2
          exit 1
        fi
      done
    fi

    case "${analysis_type}" in
      drift_explain)
        prompt_template="${analysis_root}/prompts/drift_explain.md"
        routing_task="ops.analysis"
        ;;
      slo_explain)
        prompt_template="${analysis_root}/prompts/slo_explain.md"
        routing_task="ops.analysis"
        ;;
      incident_summary)
        prompt_template="${analysis_root}/prompts/incident_summary.md"
        routing_task="ops.summary"
        ;;
      plan_review)
        prompt_template="${analysis_root}/prompts/plan_review.md"
        routing_task="code.review"
        ;;
      change_impact)
        prompt_template="${analysis_root}/prompts/change_impact.md"
        routing_task="ops.analysis"
        ;;
      compliance_summary)
        prompt_template="${analysis_root}/prompts/compliance_summary.md"
        routing_task="ops.summary"
        ;;
      *)
        echo "ERROR: unsupported analysis type: ${analysis_type}" >&2
        exit 1
        ;;
    esac

    if [[ ! -f "${prompt_template}" ]]; then
      echo "ERROR: prompt template missing: ${prompt_template}" >&2
      exit 1
    fi

    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    if [[ -z "${out_dir}" ]]; then
      out_dir="${FABRIC_REPO_ROOT}/evidence/ai/analysis/${analysis_id}/${stamp}"
    fi
    mkdir -p "${out_dir}"

    analysis_redacted="${out_dir}/analysis.yml.redacted"
    REQUESTER_ROLE="${requester_role}" TENANT_ID="${tenant_id}" \
    ANALYSIS_FILE="${analysis_file}" python3 - <<'PY' >"${analysis_redacted}"
import os

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for analysis redaction: {exc}")

analysis_file = os.environ["ANALYSIS_FILE"]
role = os.environ.get("REQUESTER_ROLE", "")
tenant_id = os.environ.get("TENANT_ID", "")

with open(analysis_file, "r", encoding="utf-8") as handle:
    payload = yaml.safe_load(handle)

if role != "operator" and tenant_id:
    payload.setdefault("tenant", {})["id"] = "redacted"

print(yaml.safe_dump(payload, sort_keys=False))
PY

    inputs_json="${out_dir}/inputs.json"
    context_md="${out_dir}/context.md"

    mcp_identity="tenant"
    if [[ "${requester_role}" == "operator" && "${tenant_id}" == "platform" ]]; then
      mcp_identity="operator"
    fi

    MCP_IDENTITY="${mcp_identity}" MCP_TENANT="${tenant_id}" \
      bash "${analysis_root}/assemble-context.sh" \
      --analysis "${analysis_file}" --out "${inputs_json}" --context "${context_md}"

    model_meta="${out_dir}/model.json"
    ROUTING_FILE="${routing_file}" ROUTING_TASK="${routing_task}" \
    PROVIDER_FILE="${provider_file}" ANALYSIS_TYPE="${analysis_type}" \
    python3 - <<'PY' >"${model_meta}"
import json
import os

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for model routing: {exc}")

routing_file = os.environ["ROUTING_FILE"]
provider_file = os.environ["PROVIDER_FILE"]
route_task = os.environ["ROUTING_TASK"]
analysis_type = os.environ["ANALYSIS_TYPE"]

routing = yaml.safe_load(open(routing_file, "r", encoding="utf-8"))
provider = yaml.safe_load(open(provider_file, "r", encoding="utf-8"))

defaults = routing.get("defaults", {})
model = None
source = "default"

for route in routing.get("routes", []):
    if route.get("task") == route_task:
        model = route.get("model")
        source = "explicit"
        break

if model is None:
    if route_task.startswith("ops."):
        model = defaults.get("ops")
    elif route_task.startswith("code."):
        model = defaults.get("code")
    elif route_task.startswith("embeddings"):
        model = defaults.get("embeddings")

if not model:
    raise SystemExit(f"ERROR: no routing model for task '{route_task}'")

payload = {
    "analysis_type": analysis_type,
    "routing_task": route_task,
    "model": model,
    "routing_source": source,
    "provider": provider.get("provider"),
    "base_url": provider.get("base_url"),
}

    print(json.dumps(payload, indent=2, sort_keys=True))
PY

    model_name="$(python3 - "${model_meta}" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(payload.get("model", ""))
PY
)"

    if [[ -n "${AI_ANALYZE_BLOCK_MODELS:-}" ]]; then
      IFS=',' read -r -a blocked_models <<<"${AI_ANALYZE_BLOCK_MODELS}"
      for blocked in "${blocked_models[@]}"; do
        if [[ "${model_name}" == "${blocked}" ]]; then
          echo "ERROR: model blocked by operator kill switch: ${model_name}" >&2
          exit 1
        fi
      done
    fi

    prompt_md="${out_dir}/prompt.md"
    TEMPLATE_PATH="${prompt_template}" CONTEXT_PATH="${context_md}" \
    ANALYSIS_ID="${analysis_id}" ANALYSIS_TYPE="${analysis_type}" \
    REQUESTER_ROLE="${requester_role}" TENANT_ID="${tenant_id_display}" \
    TENANT_SCOPE="${tenant_scope}" OUTPUT_FORMAT="${output_format}" \
    MAX_TOKENS="${max_tokens}" TIME_START="${time_start}" TIME_END="${time_end}" \
    python3 - <<'PY' >"${prompt_md}"
import os
from pathlib import Path

template = Path(os.environ["TEMPLATE_PATH"]).read_text(encoding="utf-8")
context = Path(os.environ["CONTEXT_PATH"]).read_text(encoding="utf-8")

replacements = {
    "{{analysis_id}}": os.environ.get("ANALYSIS_ID", ""),
    "{{analysis_type}}": os.environ.get("ANALYSIS_TYPE", ""),
    "{{requester_role}}": os.environ.get("REQUESTER_ROLE", ""),
    "{{tenant_id}}": os.environ.get("TENANT_ID", ""),
    "{{tenant_scope}}": os.environ.get("TENANT_SCOPE", ""),
    "{{output_format}}": os.environ.get("OUTPUT_FORMAT", ""),
    "{{max_tokens}}": os.environ.get("MAX_TOKENS", ""),
    "{{time_window_start}}": os.environ.get("TIME_START", ""),
    "{{time_window_end}}": os.environ.get("TIME_END", ""),
    "{{context}}": context.rstrip(),
}

for key, value in replacements.items():
    template = template.replace(key, value)

print(template)
PY

    output_md="${out_dir}/output.md"
    output_json="${out_dir}/output.json"

    if [[ "${cmd}" == "run" ]]; then
      if [[ "${AI_ANALYZE_EXECUTE:-0}" != "1" ]]; then
        echo "ERROR: AI_ANALYZE_EXECUTE=1 required for run" >&2
        exit 1
      fi
      if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "ERROR: live AI analysis is blocked in CI" >&2
        exit 1
      fi

      bash "${analysis_root}/call-ollama.sh" \
        --model-json "${model_meta}" --prompt "${prompt_md}" --out "${output_md}" \
        --max-tokens "${max_tokens}"
    else
      cat >"${output_md}" <<EOT
DRY RUN: AI analysis execution disabled.

Analysis: ${analysis_type}
Model task: ${routing_task}
Prompt: ${prompt_md}
EOT
    fi

    if [[ "${output_format}" == "json" ]]; then
      RESPONSE_PATH="${output_md}" python3 - <<'PY' >"${output_json}"
import json
import os
from pathlib import Path

raw = Path(os.environ["RESPONSE_PATH"]).read_text(encoding="utf-8", errors="ignore")
try:
    payload = json.loads(raw)
    print(json.dumps(payload, indent=2, sort_keys=True))
except Exception:
    wrapper = {"raw": raw}
    print(json.dumps(wrapper, indent=2, sort_keys=True))
PY
    fi

    (
      cd "${out_dir}"
      find . -type f ! -name 'manifest.sha256' ! -name 'manifest.sha256.asc' -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 sha256sum >"${out_dir}/manifest.sha256"
    )

    if [[ "${EVIDENCE_SIGN:-0}" == "1" ]]; then
      if [[ -z "${EVIDENCE_GPG_KEY:-}" ]]; then
        echo "ERROR: EVIDENCE_SIGN=1 but EVIDENCE_GPG_KEY is not set" >&2
        exit 1
      fi
      if ! command -v gpg >/dev/null 2>&1; then
        echo "ERROR: gpg not found; cannot sign evidence" >&2
        exit 1
      fi
      gpg --batch --yes --local-user "${EVIDENCE_GPG_KEY}" \
        --armor --detach-sign "${out_dir}/manifest.sha256"
    fi

    echo "OK: analysis evidence written to ${out_dir}"
    ;;

  compare)
    file_a=""
    file_b=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --file-a)
          file_a="$2"
          shift 2
          ;;
        --file-b)
          file_b="$2"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          echo "ERROR: unknown argument: $1" >&2
          usage
          exit 2
          ;;
      esac
    done

    if [[ -z "${file_a}" || -z "${file_b}" ]]; then
      usage
      exit 2
    fi

    if [[ ! -f "${file_a}" || ! -f "${file_b}" ]]; then
      echo "ERROR: comparison files not found" >&2
      exit 1
    fi

    require_cmd python3

    FILE_A="${file_a}" FILE_B="${file_b}" python3 - <<'PY'
import os

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for comparison: {exc}")

file_a = os.environ["FILE_A"]
file_b = os.environ["FILE_B"]

with open(file_a, "r", encoding="utf-8") as handle:
    a = yaml.safe_load(handle)
with open(file_b, "r", encoding="utf-8") as handle:
    b = yaml.safe_load(handle)

fields = ["analysis_id", "analysis_type", "requester_role", "tenant", "output_format", "max_tokens"]

print("AI analysis comparison")
print(f"file_a: {file_a}")
print(f"file_b: {file_b}")

for field in fields:
    av = a.get(field)
    bv = b.get(field)
    if av != bv:
        print(f"- {field}: {av} -> {bv}")

inputs_a = a.get("inputs", {})
inputs_b = b.get("inputs", {})

if inputs_a.get("evidence_refs") != inputs_b.get("evidence_refs"):
    print("- evidence_refs differ")
if inputs_a.get("time_window") != inputs_b.get("time_window"):
    print("- time_window differs")
PY
    ;;
  -h|--help|help|"")
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac
