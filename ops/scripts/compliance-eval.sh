#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  compliance-eval.sh --profile <baseline|hardened>

Options:
  --profile <name>    Required profile name
  --output <dir>      Optional output directory

Environment:
  EVIDENCE_SIGN=1           Enable GPG signing of manifest
  EVIDENCE_GPG_KEY=<fpr>    Optional signing key fingerprint

Outputs:
  evidence/compliance/<profile>/<UTC>/
    report.md
    metadata.json
    manifest.sha256
EOT
}

profile=""
output_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      profile="$2"
      shift 2
      ;;
    --output)
      output_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${profile}" ]]; then
  echo "ERROR: --profile is required" >&2
  usage
  exit 2
fi

profile_file="${FABRIC_REPO_ROOT}/compliance/profiles/${profile}.yml"
mapping_file="${FABRIC_REPO_ROOT}/compliance/mapping.yml"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found (required for compliance evaluation)" >&2
  exit 1
fi

if [[ ! -f "${profile_file}" ]]; then
  echo "ERROR: profile not found: ${profile_file}" >&2
  exit 2
fi

if [[ ! -f "${mapping_file}" ]]; then
  echo "ERROR: mapping not found: ${mapping_file}" >&2
  exit 2
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -z "${output_dir}" ]]; then
  output_dir="${FABRIC_REPO_ROOT}/evidence/compliance/${profile}/${stamp}"
fi

mkdir -p "${output_dir}"
report="${output_dir}/report.md"
metadata="${output_dir}/metadata.json"
manifest="${output_dir}/manifest.sha256"

set +e
python3 - "${profile_file}" "${mapping_file}" "${profile}" "${output_dir}" "${stamp}" "${metadata}" "${report}" "${FABRIC_REPO_ROOT}" <<'PY'
import json
import os
import sys

profile_file, mapping_file, profile_name, out_dir, stamp, meta_path, report_path, repo_root = sys.argv[1:9]

with open(profile_file, "r", encoding="utf-8") as fh:
    profile = json.load(fh)

with open(mapping_file, "r", encoding="utf-8") as fh:
    mapping = json.load(fh)

controls = profile.get("controls")
if not isinstance(controls, list):
    print("ERROR: profile controls must be a list", file=sys.stderr)
    sys.exit(2)

mapped = {item.get("id"): item for item in mapping.get("controls", [])}

results = []
summary = {"PASS": 0, "FAIL": 0, "NA": 0}

for cid in controls:
    entry = mapped.get(cid)
    if not entry:
        results.append({"id": cid, "status": "FAIL", "reason": "missing mapping"})
        summary["FAIL"] += 1
        continue

    check = entry.get("check")
    allow_na = bool(entry.get("allow_na", False))
    target = entry.get("target")

    if check == "file_exists":
        if not target:
            results.append({"id": cid, "status": "FAIL", "reason": "missing target"})
            summary["FAIL"] += 1
            continue
        path = os.path.join(repo_root, target)
        if os.path.isfile(path):
            results.append({"id": cid, "status": "PASS", "evidence": target})
            summary["PASS"] += 1
        else:
            results.append({"id": cid, "status": "FAIL", "reason": f"missing file: {target}"})
            summary["FAIL"] += 1
    elif check == "manual":
        if allow_na:
            results.append({"id": cid, "status": "NA", "reason": "manual evidence required"})
            summary["NA"] += 1
        else:
            results.append({"id": cid, "status": "FAIL", "reason": "manual evidence not allowed"})
            summary["FAIL"] += 1
    else:
        results.append({"id": cid, "status": "FAIL", "reason": f"unknown check: {check}"})
        summary["FAIL"] += 1

metadata = {
    "timestamp_utc": stamp,
    "profile": profile_name,
    "summary": summary,
}

with open(meta_path, "w", encoding="utf-8") as fh:
    json.dump(metadata, fh, indent=2, sort_keys=True)
    fh.write("\n")

with open(report_path, "w", encoding="utf-8") as fh:
    fh.write(f"# Compliance Evaluation Report — {profile_name}\n\n")
    fh.write(f"Timestamp (UTC): {stamp}\n\n")
    fh.write("## Summary\n")
    fh.write(f"- PASS: {summary['PASS']}\n")
    fh.write(f"- FAIL: {summary['FAIL']}\n")
    fh.write(f"- NA: {summary['NA']}\n\n")
    fh.write("## Results\n")
    for item in results:
        line = f"- {item['id']}: {item['status']}"
        if item.get("evidence"):
            line += f" ({item['evidence']})"
        if item.get("reason"):
            line += f" — {item['reason']}"
        fh.write(line + "\n")

# Exit code reflects FAIL count
if summary["FAIL"]:
    sys.exit(2)
PY
eval_rc=$?
set -e

(
  cd "${output_dir}"
  find . \
    -type f \
    ! -name 'manifest.sha256' \
    ! -name 'manifest.sha256.asc' \
    ! -name 'manifest.sha256.asc.a' \
    ! -name 'manifest.sha256.asc.b' \
    ! -name 'manifest.sha256.tsr' \
    -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >"${manifest}"
)

if [[ "${EVIDENCE_SIGN:-0}" -eq 1 ]]; then
  if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg not found (required for EVIDENCE_SIGN=1)" >&2
    exit 1
  fi
  gpg_args=(--batch --yes --detach-sign)
  if [[ -n "${EVIDENCE_GPG_KEY:-}" ]]; then
    gpg_args+=(--local-user "${EVIDENCE_GPG_KEY}")
  fi
  gpg "${gpg_args[@]}" --output "${manifest}.asc" "${manifest}"
fi

echo "OK: compliance evaluation completed (${profile}) -> ${output_dir}"

if [[ "${eval_rc}" -ne 0 ]]; then
  exit "${eval_rc}"
fi
