#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage:
  legal-hold-manage.sh <command> [args]

Commands:
  declare --path <evidence_dir> --hold-id <id> --declared-by <name> --reason <text> --review-date YYYY-MM-DD
    Creates a non-destructive legal-hold label pack under:
      <evidence_dir>/legal-hold/

  require-dual-control --path <evidence_dir> [--keys "<FPR_A>,<FPR_B>"]
    Marks the label pack as requiring dual signatures.

  release --path <evidence_dir> --released-by <name> --reason <text>
    Records a hold release event (no deletion).

  validate --path <evidence_dir>
    Validates that the label pack is complete and bound to the evidence manifest.

  list
    Scans ./compliance and ./forensics for active holds and prints a stable table.

Hard rules:
  - No deletion is implemented.
  - No network calls.
  - No modification of evidence contents; only writes under <evidence_dir>/legal-hold/.
  - Label packs are excluded from evidence manifests and are signed separately.
EOF
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

now_utc() {
  date -u +%Y%m%dT%H%M%SZ
}

evidence_dir=""

require_path_arg() {
  if [[ -z "${evidence_dir}" ]]; then
    echo "ERROR: missing --path <evidence_dir>" >&2
    exit 2
  fi
  if [[ ! -d "${evidence_dir}" ]]; then
    echo "ERROR: evidence dir not found: ${evidence_dir}" >&2
    exit 1
  fi
}

ensure_label_dir() {
  require_path_arg
  mkdir -p "${evidence_dir}/legal-hold"
}

write_atomic() {
  local out="$1"
  local tmp
  tmp="$(mktemp)"
  cat >"${tmp}"
  mv -f "${tmp}" "${out}"
}

write_json_atomic() {
  local out="$1"
  shift
  python3 - "${out}" "$@" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

out = sys.argv[1]
payload = json.loads(sys.argv[2])

def normalize(obj):
  if isinstance(obj, dict):
    return {k: normalize(v) for k, v in obj.items()}
  if isinstance(obj, list):
    return [normalize(v) for v in obj]
  return obj

doc = normalize(payload)

with open(out, "w", encoding="utf-8") as f:
  json.dump(doc, f, indent=2, sort_keys=True)
  f.write("\n")
PY
}

write_json_from_args_atomic() {
  local out="$1"
  shift
  local tmp
  tmp="$(mktemp)"
  python3 - "${tmp}" "$@" <<'PY'
import json
import sys

out = sys.argv[1]

with open(out, "w", encoding="utf-8") as f:
  json.dump(json.loads(sys.argv[2]), f, indent=2, sort_keys=True)
  f.write("\n")
PY
  mv -f "${tmp}" "${out}"
}

evidence_manifest_sha256() {
  local manifest="${evidence_dir}/manifest.sha256"
  if [[ ! -f "${manifest}" ]]; then
    echo "ERROR: missing evidence manifest: ${manifest}" >&2
    echo "Evidence must have a manifest.sha256 before labeling." >&2
    exit 1
  fi
  sha256sum "${manifest}" | awk '{print $1}'
}

write_binding_file() {
  local sha
  sha="$(evidence_manifest_sha256)"
  write_atomic "${evidence_dir}/legal-hold/evidence-manifest.sha256sum" <<EOF
${sha}  manifest.sha256
EOF
}

write_label_manifest() {
  (
    cd "${evidence_dir}/legal-hold"
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
      | xargs -0 sha256sum >manifest.sha256
  )
}

cmd="${1:-}"
shift $(( $# >= 1 ? 1 : $# ))

if [[ -z "${cmd}" || "${cmd}" == "-h" || "${cmd}" == "--help" ]]; then
  usage
  exit 2
fi

require_cmd date
require_cmd sha256sum
require_cmd python3
require_cmd find
require_cmd sort
require_cmd xargs

case "${cmd}" in
  declare)
    hold_id=""
    declared_by=""
    reason=""
    review_date=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --path)
          evidence_dir="${2:-}"
          shift 2
          ;;
        --hold-id)
          hold_id="${2:-}"
          shift 2
          ;;
        --declared-by)
          declared_by="${2:-}"
          shift 2
          ;;
        --reason)
          reason="${2:-}"
          shift 2
          ;;
        --review-date)
          review_date="${2:-}"
          shift 2
          ;;
        *)
          echo "ERROR: unknown argument: $1" >&2
          usage
          exit 2
          ;;
      esac
    done

    if [[ -z "${hold_id}" || -z "${declared_by}" || -z "${reason}" || -z "${review_date}" ]]; then
      echo "ERROR: declare requires --hold-id, --declared-by, --reason, --review-date" >&2
      exit 2
    fi

    ensure_label_dir

    ts="$(now_utc)"
    write_binding_file

    write_atomic "${evidence_dir}/legal-hold/LEGAL_HOLD" <<EOF
hold_id=${hold_id}
declared_at_utc=${ts}
EOF

    evidence_sha="$(evidence_manifest_sha256)"
    payload="$(
      python3 - "${hold_id}" "${declared_by}" "${ts}" "${review_date}" "${reason}" "${evidence_dir}" "${evidence_sha}" <<'PY'
import json
import sys

hold_id, declared_by, declared_at_utc, review_date, reason, evidence_path, evidence_sha = sys.argv[1:8]

doc = {
  "hold_id": hold_id,
  "declared_by": declared_by,
  "declared_at_utc": declared_at_utc,
  "review_date": review_date,
  "reason": reason,
  "evidence": {
    "path": evidence_path,
    "manifest_file": "manifest.sha256",
    "manifest_sha256": evidence_sha,
  },
  "labels_dir": "legal-hold",
}

print(json.dumps(doc, separators=(",", ":")))
PY
    )"
    write_json_from_args_atomic "${evidence_dir}/legal-hold/hold.json" "${payload}"

    write_label_manifest
    echo "OK: declared legal hold label pack: ${evidence_dir}/legal-hold"
    ;;

  require-dual-control)
    keys=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --path)
          evidence_dir="${2:-}"
          shift 2
          ;;
        --keys)
          keys="${2:-}"
          shift 2
          ;;
        *)
          echo "ERROR: unknown argument: $1" >&2
          usage
          exit 2
          ;;
      esac
    done

    ensure_label_dir
    write_binding_file

    printf '%s\n' "DUAL_CONTROL_REQUIRED" >"${evidence_dir}/legal-hold/DUAL_CONTROL_REQUIRED"

    keys_json="null"
    if [[ -n "${keys}" ]]; then
      IFS=',' read -r key_a key_b extra <<<"${keys}"
      if [[ -z "${key_a// /}" || -z "${key_b// /}" || -n "${extra:-}" ]]; then
        echo "ERROR: --keys must contain exactly two comma-separated fingerprints." >&2
        exit 2
      fi
      keys_json="$(
        python3 - "${key_a}" "${key_b}" <<'PY'
import json
import sys
print(json.dumps([sys.argv[1], sys.argv[2]]))
PY
      )"
    fi

    payload="$(
      python3 - "${keys_json}" <<'PY'
import json
import sys

keys = json.loads(sys.argv[1]) if sys.argv[1] != "null" else None

doc = {
  "required_signatures": [
    {"role": "custodian_a", "fingerprint": (keys[0] if keys else None), "signature_file": "manifest.sha256.asc.a"},
    {"role": "custodian_b", "fingerprint": (keys[1] if keys else None), "signature_file": "manifest.sha256.asc.b"},
  ]
}
print(json.dumps(doc, separators=(",", ":")))
PY
    )"
    write_json_atomic "${evidence_dir}/legal-hold/approvals.json" "${payload}"

    write_label_manifest
    echo "OK: dual-control required for label pack: ${evidence_dir}/legal-hold"
    ;;

  release)
    released_by=""
    reason=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --path)
          evidence_dir="${2:-}"
          shift 2
          ;;
        --released-by)
          released_by="${2:-}"
          shift 2
          ;;
        --reason)
          reason="${2:-}"
          shift 2
          ;;
        *)
          echo "ERROR: unknown argument: $1" >&2
          usage
          exit 2
          ;;
      esac
    done

    if [[ -z "${released_by}" || -z "${reason}" ]]; then
      echo "ERROR: release requires --released-by and --reason" >&2
      exit 2
    fi

    require_path_arg
    if [[ ! -d "${evidence_dir}/legal-hold" ]]; then
      echo "ERROR: missing legal-hold label pack: ${evidence_dir}/legal-hold" >&2
      exit 1
    fi

    ts="$(now_utc)"
    write_binding_file

    payload="$(
      python3 - "${released_by}" "${ts}" "${reason}" <<'PY'
import json
import sys

released_by, released_at_utc, reason = sys.argv[1:4]
print(json.dumps({"released_by": released_by, "released_at_utc": released_at_utc, "reason": reason}, separators=(",", ":")))
PY
    )"
    write_json_from_args_atomic "${evidence_dir}/legal-hold/release.json" "${payload}"

    write_label_manifest
    echo "OK: recorded hold release (labels only): ${evidence_dir}/legal-hold"
    ;;

  validate)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --path)
          evidence_dir="${2:-}"
          shift 2
          ;;
        *)
          echo "ERROR: unknown argument: $1" >&2
          usage
          exit 2
          ;;
      esac
    done

    require_path_arg

    python3 - "${evidence_dir}" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
lh = root / "legal-hold"

def fail(msg: str) -> None:
  print(f"ERROR: {msg}", file=sys.stderr)
  sys.exit(1)

if not (root / "manifest.sha256").is_file():
  fail("missing evidence manifest.sha256")

if not lh.is_dir():
  fail("missing legal-hold directory")

required = ["LEGAL_HOLD", "hold.json", "evidence-manifest.sha256sum", "manifest.sha256"]
for name in required:
  if not (lh / name).is_file():
    fail(f"missing legal-hold/{name}")

try:
  hold = json.loads((lh / "hold.json").read_text(encoding="utf-8"))
except Exception as e:
  fail(f"hold.json is not valid JSON: {e}")

for key in ["hold_id", "declared_by", "declared_at_utc", "review_date", "reason", "evidence"]:
  if key not in hold or hold[key] in ("", None):
    fail(f"hold.json missing required field: {key}")

e = hold.get("evidence") or {}
for key in ["manifest_file", "manifest_sha256"]:
  if key not in e or e[key] in ("", None):
    fail(f"hold.json evidence missing field: {key}")

print(f"OK: legal-hold pack valid: {lh}")
PY
    ;;

  list)
    python3 - "${REPO_ROOT}" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
paths = []
for base in ["compliance", "forensics"]:
  p = root / base
  if p.is_dir():
    paths.append(p)

rows = []
for base in paths:
  for marker in base.rglob("legal-hold/LEGAL_HOLD"):
    lh = marker.parent
    hold_json = lh / "hold.json"
    if not hold_json.is_file():
      continue
    try:
      hold = json.loads(hold_json.read_text(encoding="utf-8"))
    except Exception:
      continue
    evidence_dir = str(lh.parent.relative_to(root))
    hold_id = str(hold.get("hold_id", "unknown"))
    declared_at = str(hold.get("declared_at_utc", "unknown"))
    review_date = str(hold.get("review_date", "unknown"))
    released = "yes" if (lh / "release.json").is_file() else "no"
    rows.append((hold_id, evidence_dir, declared_at, review_date, released))

rows.sort(key=lambda r: (r[0], r[1]))

print("HOLD_ID\tEVIDENCE_DIR\tDECLARED_AT_UTC\tREVIEW_DATE\tRELEASED")
for r in rows:
  print("\t".join(r))
PY
    ;;

  *)
    echo "ERROR: unknown command: ${cmd}" >&2
    usage
    exit 2
    ;;
esac
