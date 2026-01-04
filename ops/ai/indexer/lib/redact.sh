#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"

index_mode="${INDEX_MODE:-offline}"
if [[ "${index_mode}" == "live" ]]; then
  require_operator_mode
else
  require_ci_mode
fi


usage() {
  cat >&2 <<'EOT'
Usage:
  redact.sh --file <path> --patterns <path> --out <path> --report <path>
EOT
}

file_path=""
patterns_path=""
out_path=""
report_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      file_path="$2"
      shift 2
      ;;
    --patterns)
      patterns_path="$2"
      shift 2
      ;;
    --out)
      out_path="$2"
      shift 2
      ;;
    --report)
      report_path="$2"
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

if [[ -z "${file_path}" || -z "${patterns_path}" || -z "${out_path}" || -z "${report_path}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${file_path}" ]]; then
  echo "ERROR: file not found: ${file_path}" >&2
  exit 1
fi

if [[ ! -f "${patterns_path}" ]]; then
  echo "ERROR: patterns file not found: ${patterns_path}" >&2
  exit 1
fi

FILE_PATH="${file_path}" PATTERNS_PATH="${patterns_path}" OUT_PATH="${out_path}" REPORT_PATH="${report_path}" python3 - <<'PY'
import json
import os
import re
from pathlib import Path

file_path = Path(os.environ["FILE_PATH"])
patterns_path = Path(os.environ["PATTERNS_PATH"])
out_path = Path(os.environ["OUT_PATH"])
report_path = Path(os.environ["REPORT_PATH"])

text = file_path.read_text(encoding="utf-8", errors="ignore")
patterns = [line.strip() for line in patterns_path.read_text(encoding="utf-8").splitlines() if line.strip()]

matches = []
for pattern in patterns:
    if re.search(pattern, text):
        matches.append(pattern)

denied = bool(matches)

report = {
    "file": str(file_path),
    "denied": denied,
    "matches": matches,
}
report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

if denied:
    raise SystemExit(2)

out_path.write_text(text, encoding="utf-8")
PY
