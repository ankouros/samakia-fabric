#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage: redact.sh --in <path> --out <path>
EOT
}

in_path=""
out_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --in)
      in_path="$2"
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

if [[ -z "${in_path}" || -z "${out_path}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${in_path}" ]]; then
  echo "ERROR: redact input missing: ${in_path}" >&2
  exit 1
fi

indexing_file="${INDEXING_FILE:-${FABRIC_REPO_ROOT}/contracts/ai/indexing.yml}"

REQUESTER_ROLE="${REQUESTER_ROLE:-}" TENANT_ID="${TENANT_ID:-}" \
INPUT_PATH="${in_path}" OUTPUT_PATH="${out_path}" INDEXING_FILE="${indexing_file}" \
python3 - <<'PY'
import os
import re
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for redaction: {exc}")

input_path = Path(os.environ["INPUT_PATH"])
output_path = Path(os.environ["OUTPUT_PATH"])
indexing_file = Path(os.environ["INDEXING_FILE"])
role = os.environ.get("REQUESTER_ROLE", "")
tenant_id = os.environ.get("TENANT_ID", "")

text = input_path.read_text(encoding="utf-8", errors="ignore")
patterns = []

if indexing_file.exists():
    payload = yaml.safe_load(indexing_file.read_text(encoding="utf-8")) or {}
    redaction = payload.get("redaction", {}) if isinstance(payload, dict) else {}
    patterns = [p for p in redaction.get("deny_patterns", []) if isinstance(p, str)]

redacted_lines = []
for line in text.splitlines():
    if any(re.search(pattern, line) for pattern in patterns):
        redacted_lines.append("[REDACTED]")
    else:
        redacted_lines.append(line)

redacted = "\n".join(redacted_lines)

if role != "operator" and tenant_id:
    redacted = redacted.replace(tenant_id, "[REDACTED_TENANT]")

for pattern in patterns:
    if re.search(pattern, redacted):
        raise SystemExit("ERROR: redaction incomplete; secret pattern remains")

output_path.write_text(redacted + "\n", encoding="utf-8")
PY
