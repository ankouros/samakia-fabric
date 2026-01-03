#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage: call-ollama.sh --model-json <path> --prompt <path> --out <path> --max-tokens <int>
EOT
}

model_json=""
prompt_path=""
out_path=""
max_tokens=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model-json)
      model_json="$2"
      shift 2
      ;;
    --prompt)
      prompt_path="$2"
      shift 2
      ;;
    --out)
      out_path="$2"
      shift 2
      ;;
    --max-tokens)
      max_tokens="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${model_json}" || -z "${prompt_path}" || -z "${out_path}" || -z "${max_tokens}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${model_json}" ]]; then
  echo "ERROR: model metadata missing: ${model_json}" >&2
  exit 1
fi

if [[ ! -f "${prompt_path}" ]]; then
  echo "ERROR: prompt file missing: ${prompt_path}" >&2
  exit 1
fi

if [[ "${AI_ANALYZE_EXECUTE:-0}" != "1" ]]; then
  echo "ERROR: AI_ANALYZE_EXECUTE=1 required" >&2
  exit 1
fi

if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
  echo "ERROR: live AI analysis is blocked in CI" >&2
  exit 1
fi

response_path="$(mktemp)"

MODEL_JSON="${model_json}" PROMPT_PATH="${prompt_path}" \
MAX_TOKENS="${max_tokens}" python3 - <<'PY' >"${response_path}"
import json
import os
from pathlib import Path

model_json = json.loads(Path(os.environ["MODEL_JSON"]).read_text(encoding="utf-8"))
prompt = Path(os.environ["PROMPT_PATH"]).read_text(encoding="utf-8")
max_tokens = int(os.environ.get("MAX_TOKENS", "0"))

payload = {
    "model": model_json.get("model"),
    "prompt": prompt,
    "stream": False,
    "options": {"num_predict": max_tokens},
}

print(json.dumps(payload))
PY

base_url="$(python3 - "${model_json}" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(payload.get("base_url", ""))
PY
)"

model_name="$(python3 - "${model_json}" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(payload.get("model", ""))
PY
)"

if [[ -z "${base_url}" || -z "${model_name}" ]]; then
  echo "ERROR: model metadata missing base_url or model" >&2
  exit 1
fi

payload_path="$(mktemp)"
cp "${response_path}" "${payload_path}"

result_path="$(mktemp)"
if ! curl -sS -H "Content-Type: application/json" -d @"${payload_path}" \
  "${base_url}/api/generate" >"${result_path}"; then
  echo "ERROR: Ollama request failed" >&2
  cat "${result_path}" >&2 || true
  exit 1
fi

RESPONSE_PATH="${result_path}" python3 - <<'PY' >"${out_path}"
import json
import os
from pathlib import Path

payload = json.loads(Path(os.environ["RESPONSE_PATH"]).read_text(encoding="utf-8"))
if payload.get("error"):
    raise SystemExit(f"ERROR: Ollama error: {payload['error']}")

response = payload.get("response")
if response is None:
    raise SystemExit("ERROR: Ollama response missing 'response' field")

print(response, end="")
PY
