#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage:
  correlation-timeline-builder.sh <correlation-id> <evidence_dir...>

Inputs:
  evidence_dir may be:
    - a snapshot directory that contains manifest.sha256 (e.g., forensics/INC-1/snapshot-20250101T010203Z)
    - an incident directory that contains snapshot-* subdirs (e.g., forensics/INC-1)

Output (derived artifacts; ignored by Git):
  correlation/<correlation-id>/
    timeline.csv
    timeline.md
    manifest.sha256

Hard rules:
  - Read-only: does not modify evidence packs.
  - No network calls.
  - Does not sign; use compliance-snapshot.sh in sign-only mode if required.
EOF
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

correlation_id="${1:-}"
shift $(( $# >= 1 ? 1 : $# ))

if [[ -z "${correlation_id}" || $# -lt 1 ]]; then
  usage
  exit 2
fi

require_cmd python3
require_cmd sha256sum
require_cmd find
require_cmd sort
require_cmd xargs
require_cmd mkdir
require_cmd date
require_cmd mktemp

out_dir="${REPO_ROOT}/correlation/${correlation_id}"
mkdir -p "${out_dir}"

timeline_csv="${out_dir}/timeline.csv"
timeline_md="${out_dir}/timeline.md"

tmp_snapshots="$(mktemp)"
snapshots_sorted=""
cleanup() {
  rm -f "${tmp_snapshots}" "${snapshots_sorted}" 2>/dev/null || true
}
trap cleanup EXIT

for input in "$@"; do
  abs="${input}"
  if [[ "${abs}" != /* ]]; then
    abs="${REPO_ROOT}/${input}"
  fi
  if [[ ! -d "${abs}" ]]; then
    echo "ERROR: input directory not found: ${input}" >&2
    exit 1
  fi

  if [[ -f "${abs}/manifest.sha256" ]]; then
    printf '%s\n' "${abs}" >>"${tmp_snapshots}"
    continue
  fi

  while IFS= read -r -d '' snap; do
    if [[ -f "${snap}/manifest.sha256" ]]; then
      printf '%s\n' "${snap}" >>"${tmp_snapshots}"
    fi
  done < <(find "${abs}" -maxdepth 2 -type d -name 'snapshot-*' -print0 2>/dev/null || true)
done

snapshots_sorted="$(mktemp)"
LC_ALL=C sort -u "${tmp_snapshots}" >"${snapshots_sorted}"

if [[ ! -s "${snapshots_sorted}" ]]; then
  echo "ERROR: no snapshots found (expected manifest.sha256 under snapshot dirs)" >&2
  exit 1
fi

python3 - "${REPO_ROOT}" "${timeline_csv}" "${timeline_md}" "${correlation_id}" "${snapshots_sorted}" <<'PY'
import csv
import json
import os
import re
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
csv_out = Path(sys.argv[2])
md_out = Path(sys.argv[3])
corr_id = sys.argv[4]
snapshot_list = Path(sys.argv[5])

snapshot_dirs = [Path(line.strip()) for line in snapshot_list.read_text(encoding="utf-8").splitlines() if line.strip()]

def relpath(p: Path) -> str:
  try:
    return str(p.relative_to(repo_root))
  except Exception:
    return str(p)

def infer_incident_id(snapshot_dir: Path) -> str:
  # Expected: forensics/<incident-id>/snapshot-...
  parts = relpath(snapshot_dir).split("/")
  if len(parts) >= 3 and parts[0] == "forensics" and parts[2].startswith("snapshot-"):
    return parts[1]
  return "unknown"

def load_metadata(snapshot_dir: Path) -> dict:
  path = snapshot_dir / "metadata.json"
  if not path.exists():
    return {}
  try:
    return json.loads(path.read_text(encoding="utf-8"))
  except Exception:
    return {}

def guess_timestamp_utc(snapshot_dir: Path, meta: dict) -> str:
  ts = meta.get("timestamp_utc")
  if isinstance(ts, str) and ts.strip():
    return ts.strip()
  # Fallback: snapshot-YYYYMMDDTHHMMSSZ
  m = re.search(r"snapshot-(\\d{8}T\\d{6}Z)$", snapshot_dir.name)
  return m.group(1) if m else "unknown"

def guess_collector(meta: dict) -> str:
  collector = meta.get("collector") or {}
  if isinstance(collector, dict):
    user = collector.get("user")
    if isinstance(user, str) and user.strip():
      return user.strip()
  return "unknown"

def event_type_for(rel_file: str) -> str:
  if rel_file.startswith("./logs/") or rel_file.startswith("logs/"):
    return "auth"
  if rel_file.startswith("./network/") or rel_file.startswith("network/"):
    return "network"
  if rel_file.startswith("./system/") or rel_file.startswith("system/"):
    return "process"
  if rel_file.startswith("./integrity/") or rel_file.startswith("integrity/"):
    return "integrity"
  if rel_file.startswith("./packages/") or rel_file.startswith("packages/"):
    return "package"
  if rel_file.startswith("./apps/") or rel_file.startswith("apps/"):
    return "app"
  if rel_file in ("./metadata.json", "metadata.json", "./timeline.txt", "timeline.txt"):
    return "meta"
  return "other"

rows: list[dict[str, str]] = []

for snap in snapshot_dirs:
  manifest = snap / "manifest.sha256"
  if not manifest.exists():
    continue

  meta = load_metadata(snap)
  ts = guess_timestamp_utc(snap, meta)
  collector = guess_collector(meta)
  incident_id = infer_incident_id(snap)

  for line in manifest.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line:
      continue
    # Format: "<sha256>  <path>"
    parts = line.split()
    if len(parts) < 2:
      continue
    sha = parts[0]
    rel_file = " ".join(parts[1:]).strip()
    # Keep stable reference format: <evidence_path>/<rel_file>:sha256=<sha>
    evidence_path = f"{relpath(snap)}/{rel_file.lstrip('./')}"
    evidence_ref = f"{evidence_path}:sha256={sha}"

    rows.append(
      {
        "timestamp_utc": ts,
        "incident_id": incident_id,
        "evidence_ref": evidence_ref,
        "event_type": event_type_for(rel_file),
        "description": f"Collected artifact: {rel_file.lstrip('./')}",
        "collector": f"collector:{collector}",
        "confidence": "high",
      }
    )

rows.sort(key=lambda r: (r["timestamp_utc"], r["incident_id"], r["evidence_ref"]))

csv_out.parent.mkdir(parents=True, exist_ok=True)
with csv_out.open("w", encoding="utf-8", newline="") as f:
  w = csv.DictWriter(
    f,
    fieldnames=[
      "timestamp_utc",
      "incident_id",
      "evidence_ref",
      "event_type",
      "description",
      "collector",
      "confidence",
    ],
  )
  w.writeheader()
  w.writerows(rows)

# Minimal markdown view for humans
md_lines = [
  f"# Correlation Timeline — {corr_id}",
  "",
  "Derived artifact (read-only analysis output):",
  "- Facts only; no hypotheses in this timeline",
  "- Evidence is referenced by path + sha256 from original manifests",
  "",
  "| timestamp_utc | incident_id | event_type | description | evidence_ref | confidence |",
  "|---|---:|---|---|---|---|",
]
for r in rows:
  md_lines.append(
    f"| {r['timestamp_utc']} | {r['incident_id']} | {r['event_type']} | {r['description']} | {r['evidence_ref']} | {r['confidence']} |"
  )
md_out.write_text("\n".join(md_lines) + "\n", encoding="utf-8")
print(f"OK: wrote {relpath(csv_out)} ({len(rows)} rows)")
print(f"OK: wrote {relpath(md_out)}")
PY

# Derived manifest for the correlation pack
(
  cd "${out_dir}"
  find . \
    -path './legal-hold' -prune -o \
    -type f \
    ! -name 'manifest.sha256' \
    ! -name 'manifest.sha256.asc' \
    ! -name 'manifest.sha256.asc.a' \
    ! -name 'manifest.sha256.asc.b' \
    ! -name 'manifest.sha256.tsr' \
    ! -name 'tsa-metadata.json' \
    -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >manifest.sha256
)

echo "OK: wrote derived correlation manifest: ${out_dir}/manifest.sha256"
echo "Next (optional): sign/notarize it via:"
echo "  COMPLIANCE_SNAPSHOT_DIR=\"${out_dir}\" bash ops/scripts/compliance-snapshot.sh <env>"
