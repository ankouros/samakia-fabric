#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOT'
Usage:
  json.sh --out <path> --data <json>
EOT
}

out_path=""
data=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      out_path="$2"
      shift 2
      ;;
    --data)
      data="$2"
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

if [[ -z "${out_path}" || -z "${data}" ]]; then
  usage
  exit 2
fi

DATA="${data}" OUT_PATH="${out_path}" python3 - <<'PY'
import json
import os
from pathlib import Path

payload = json.loads(os.environ["DATA"])
Path(os.environ["OUT_PATH"]).write_text(
    json.dumps(payload, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
