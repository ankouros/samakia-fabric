#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  plan-review.sh --plan <path> [--env <name>] [--out-dir <path>]

Produces a read-only plan review packet under:
  evidence/ai/plan-review/<env>/<UTC>/

Options:
  --plan PATH    Terraform plan output (text file)
  --env NAME     Environment label (default: unknown)
  --out-dir DIR  Override output directory
EOT
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

plan_path=""
env_name="unknown"
out_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)
      plan_path="${2:-}"
      shift 2
      ;;
    --env)
      env_name="${2:-unknown}"
      shift 2
      ;;
    --out-dir)
      out_dir="${2:-}"
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

if [[ -z "${plan_path}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${plan_path}" ]]; then
  echo "ERROR: plan file not found: ${plan_path}" >&2
  exit 1
fi

require_cmd date
require_cmd git
require_cmd python3
require_cmd sha256sum
require_cmd find
require_cmd sort
require_cmd xargs

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
commit_short="$(git -C "${FABRIC_REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

if [[ -z "${out_dir}" ]]; then
  out_dir="${FABRIC_REPO_ROOT}/evidence/ai/plan-review/${env_name}/${stamp}"
fi
mkdir -p "${out_dir}"

report_path="${out_dir}/report.md"
findings_path="${out_dir}/findings.json"
meta_path="${out_dir}/metadata.json"
manifest_path="${out_dir}/manifest.sha256"

python3 - "${plan_path}" "${report_path}" "${findings_path}" "${meta_path}" "${env_name}" "${stamp}" "${commit_short}" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

plan_path, report_path, findings_path, meta_path, env_name, stamp, commit_short = sys.argv[1:8]

plan_text = Path(plan_path).read_text(encoding="utf-8", errors="ignore")

summary = "Summary unavailable"
adds = changes = destroys = None

if "No changes." in plan_text:
    summary = "No changes. Infrastructure matches the configuration."
else:
    match = re.search(r"Plan: (\d+) to add, (\d+) to change, (\d+) to destroy", plan_text)
    if match:
        adds, changes, destroys = map(int, match.groups())
        summary = f"Plan: {adds} to add, {changes} to change, {destroys} to destroy."

findings = []
if "Error:" in plan_text:
    findings.append({
        "id": "tf-plan-error",
        "severity": "high",
        "summary": "Terraform plan reported an error.",
    })

if destroys is not None and destroys > 0:
    findings.append({
        "id": "tf-destroy",
        "severity": "high",
        "summary": f"Plan destroys {destroys} resources.",
    })

if adds is not None or changes is not None:
    if (adds or 0) > 0 or (changes or 0) > 0:
        findings.append({
            "id": "tf-change",
            "severity": "medium",
            "summary": "Plan contains create/update operations.",
        })

if not findings:
    findings.append({
        "id": "tf-noop",
        "severity": "info",
        "summary": "Plan is read-only or reports no changes.",
    })

report = """# Terraform Plan Review\n\n"""
report += f"Environment: {env_name}\n\n"
report += f"Timestamp (UTC): {stamp}\n\n"
report += f"Commit: {commit_short}\n\n"
report += f"Plan source: {os.path.basename(plan_path)}\n\n"
report += f"Summary: {summary}\n\n"
report += "## Findings\n"
for item in findings:
    report += f"- [{item['severity']}] {item['summary']} ({item['id']})\n"

Path(report_path).write_text(report, encoding="utf-8")

with open(findings_path, "w", encoding="utf-8") as fh:
    json.dump({"findings": findings}, fh, indent=2, sort_keys=True)
    fh.write("\n")

meta = {
    "environment": env_name,
    "timestamp_utc": stamp,
    "commit_short": commit_short,
    "plan_source": os.path.basename(plan_path),
    "summary": summary,
    "type": "plan-review",
}

with open(meta_path, "w", encoding="utf-8") as fh:
    json.dump(meta, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

(
  cd "${out_dir}"
  find . -type f ! -name 'manifest.sha256' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >"${manifest_path}"
)

if [[ "${EVIDENCE_SIGN:-0}" == "1" ]]; then
  if [[ -z "${EVIDENCE_GPG_KEY:-}" ]]; then
    echo "ERROR: EVIDENCE_SIGN=1 but EVIDENCE_GPG_KEY is not set" >&2
    exit 1
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg not found; cannot sign evidence" >&2
    exit 1
  fi
  gpg --batch --yes --local-user "${EVIDENCE_GPG_KEY}" \
    --armor --detach-sign "${manifest_path}"
fi

echo "OK: plan review packet written to ${out_dir}"
