#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export FABRIC_REPO_ROOT="${ROOT_DIR}"

stamp="1970-01-01T00:00:00Z"
packet_dir="${ROOT_DIR}/evidence/release-readiness/phase12/${stamp}"

rm -rf "${packet_dir}"

TENANT=all READINESS_STAMP="${stamp}" \
  bash "${ROOT_DIR}/ops/release/phase12/phase12-readiness-packet.sh"

if [[ ! -f "${packet_dir}/manifest.sha256" ]]; then
  echo "ERROR: manifest.sha256 missing" >&2
  exit 1
fi

if [[ ! -f "${packet_dir}/manifest.json" ]]; then
  echo "ERROR: manifest.json missing" >&2
  exit 1
fi

PACKET_DIR="${packet_dir}" python3 - <<'PY'
import json
import os
from pathlib import Path

packet_dir = Path(os.environ["PACKET_DIR"])

manifest = packet_dir / "manifest.json"
files = json.loads(manifest.read_text()).get("files", [])
paths = [entry.get("path") for entry in files]
if paths != sorted(paths):
    raise SystemExit("ERROR: manifest.json files are not sorted")

sha_manifest = packet_dir / "manifest.sha256"
paths = []
for line in sha_manifest.read_text().splitlines():
    parts = line.split()
    if len(parts) < 2:
        continue
    paths.append(parts[1])
if paths != sorted(paths):
    raise SystemExit("ERROR: manifest.sha256 entries are not sorted by path")
PY

rm -rf "${packet_dir}"

echo "PASS: readiness packet determinism checks"
