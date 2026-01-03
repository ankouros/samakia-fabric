#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  phase12-readiness-manifest.sh <packet-dir>

Environment:
  MANIFEST_STAMP
  MANIFEST_COMMIT
  MANIFEST_ENV
  MANIFEST_TENANT
  MANIFEST_STATUS
EOT
}

packet_dir="${1:-}"
if [[ -z "${packet_dir}" ]]; then
  usage
  exit 2
fi

if [[ ! -d "${packet_dir}" ]]; then
  echo "ERROR: packet dir not found: ${packet_dir}" >&2
  exit 1
fi

manifest_sha="${packet_dir}/manifest.sha256"

MANIFEST_STAMP="${MANIFEST_STAMP:-unknown}" \
MANIFEST_COMMIT="${MANIFEST_COMMIT:-unknown}" \
MANIFEST_ENV="${MANIFEST_ENV:-unknown}" \
MANIFEST_TENANT="${MANIFEST_TENANT:-unknown}" \
MANIFEST_STATUS="${MANIFEST_STATUS:-UNKNOWN}" \
PACKET_DIR="${packet_dir}" \
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

packet_dir = Path(os.environ["PACKET_DIR"])

stamp = os.environ.get("MANIFEST_STAMP", "unknown")
commit = os.environ.get("MANIFEST_COMMIT", "unknown")
env_name = os.environ.get("MANIFEST_ENV", "unknown")
tenant = os.environ.get("MANIFEST_TENANT", "unknown")
status = os.environ.get("MANIFEST_STATUS", "UNKNOWN")

exclude_names = {
    "manifest.json",
    "manifest.sha256",
    "manifest.sha256.asc",
    "manifest.sha256.asc.a",
    "manifest.sha256.asc.b",
    "manifest.sha256.tsr",
    "tsa-metadata.json",
}

files = []
for path in sorted(packet_dir.rglob("*")):
    if not path.is_file():
        continue
    if path.name in exclude_names:
        continue
    rel = path.relative_to(packet_dir).as_posix()
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    files.append({
        "path": rel,
        "sha256": digest,
        "bytes": path.stat().st_size,
    })

payload = {
    "packet": "phase12-release-readiness",
    "timestamp_utc": stamp,
    "commit": commit,
    "environment": env_name,
    "tenant": tenant,
    "overall_status": status,
    "files": files,
    "notes": [
        "This manifest tracks redacted packet contents only.",
        "Use manifest.sha256 for integrity verification.",
    ],
}

(packet_dir / "manifest.json").write_text(
    json.dumps(payload, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

(
  cd "${packet_dir}"
  find . \
    -type f \
    ! -name 'manifest.sha256' \
    ! -name 'manifest.sha256.asc' \
    ! -name 'manifest.sha256.asc.a' \
    ! -name 'manifest.sha256.asc.b' \
    ! -name 'manifest.sha256.tsr' \
    ! -name 'tsa-metadata.json' \
    -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum > "${manifest_sha}"
)
