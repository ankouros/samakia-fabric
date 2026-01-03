#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage: evidence.sh --ref <path> --out <path>
EOT
}

ref_path=""
out_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      ref_path="$2"
      shift 2
      ;;
    --out)
      out_path="$2"
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

if [[ -z "${ref_path}" || -z "${out_path}" ]]; then
  usage
  exit 2
fi

mcp_url="${MCP_EVIDENCE_URL:-http://127.0.0.1:8782}"
identity="${MCP_IDENTITY:-operator}"
tenant="${MCP_TENANT:-platform}"
request_id="${MCP_REQUEST_ID:-}"

payload="$(REF_PATH="${ref_path}" python3 - <<'PY'
import json
import os

ref_path = os.environ.get("REF_PATH", "")
print(json.dumps({"action": "read_file", "params": {"path": ref_path}}))
PY
)"

headers=(
  -H "Content-Type: application/json"
  -H "X-MCP-Identity: ${identity}"
  -H "X-MCP-Tenant: ${tenant}"
)

if [[ -n "${request_id}" ]]; then
  headers+=( -H "X-MCP-Request-Id: ${request_id}" )
fi

response_path="$(mktemp)"
if ! curl -sS "${headers[@]}" -d "${payload}" "${mcp_url}/query" >"${response_path}"; then
  echo "ERROR: MCP evidence request failed" >&2
  cat "${response_path}" >&2 || true
  exit 1
fi

RESPONSE_PATH="${response_path}" python3 - <<'PY' >"${out_path}"
import json
import os
from pathlib import Path

payload = json.loads(Path(os.environ["RESPONSE_PATH"]).read_text(encoding="utf-8"))
if not payload.get("ok"):
    raise SystemExit(f"ERROR: MCP evidence response not ok: {payload.get('error')}")

content = payload.get("data", {}).get("content")
if content is None:
    raise SystemExit("ERROR: MCP evidence response missing content")

print(content, end="")
PY
