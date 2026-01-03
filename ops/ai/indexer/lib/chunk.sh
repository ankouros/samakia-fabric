#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  chunk.sh --file <path> --max-chars <n> --overlap <n> [--out <path>]
EOT
}

file_path=""
max_chars=""
overlap=""
out_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      file_path="$2"
      shift 2
      ;;
    --max-chars)
      max_chars="$2"
      shift 2
      ;;
    --overlap)
      overlap="$2"
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

if [[ -z "${file_path}" || -z "${max_chars}" || -z "${overlap}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${file_path}" ]]; then
  echo "ERROR: file not found: ${file_path}" >&2
  exit 1
fi

FILE_PATH="${file_path}" MAX_CHARS="${max_chars}" OVERLAP="${overlap}" OUT_PATH="${out_path}" python3 - <<'PY'
import json
import os
from pathlib import Path

file_path = Path(os.environ["FILE_PATH"])
max_chars = int(os.environ["MAX_CHARS"])
overlap = int(os.environ["OVERLAP"])
out_path = os.environ.get("OUT_PATH")

text = file_path.read_text(encoding="utf-8", errors="ignore")

chunks = []
start = 0
length = len(text)

while start < length:
    end = min(start + max_chars, length)
    chunk_text = text[start:end]
    chunks.append({"start": start, "end": end, "text": chunk_text})
    if end == length:
        break
    start = max(0, end - overlap)

payload = {"file": str(file_path), "chunks": chunks}

if out_path:
    Path(out_path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
else:
    print(json.dumps(payload, indent=2, sort_keys=True))
PY
