#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
usage: evidence.sh --tenant <id> --workload <id> --env <env> --plan <plan.json> --approval <approval.json> --decision <decision.json>
EOT
}

tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"
plan_file=""
approval_file=""
decision_file=""
diff_file=""
artifacts_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)
      tenant="$2"
      shift 2
      ;;
    --workload)
      workload="$2"
      shift 2
      ;;
    --env)
      env_name="$2"
      shift 2
      ;;
    --plan)
      plan_file="$2"
      shift 2
      ;;
    --approval)
      approval_file="$2"
      shift 2
      ;;
    --decision)
      decision_file="$2"
      shift 2
      ;;
    --diff)
      diff_file="$2"
      shift 2
      ;;
    --artifacts)
      artifacts_file="$2"
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

if [[ -z "${tenant}" || -z "${workload}" || -z "${env_name}" || -z "${plan_file}" || -z "${approval_file}" || -z "${decision_file}" ]]; then
  usage
  exit 2
fi

for path in "${plan_file}" "${approval_file}" "${decision_file}"; do
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: input file not found: ${path}" >&2
    exit 1
  fi
done

stamp="${EVIDENCE_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
out_dir="${EVIDENCE_DIR:-${FABRIC_REPO_ROOT}/evidence/exposure-apply/${tenant}/${workload}/${stamp}}"

mkdir -p "${out_dir}"

redacted_plan="${out_dir}/plan.json"
redacted_approval="${out_dir}/approval.json"

bash "${FABRIC_REPO_ROOT}/ops/exposure/apply/redact.sh" "${plan_file}" "${redacted_plan}"
bash "${FABRIC_REPO_ROOT}/ops/exposure/apply/redact.sh" "${approval_file}" "${redacted_approval}"

cp "${decision_file}" "${out_dir}/decision.json"

if [[ -n "${diff_file}" && -f "${diff_file}" ]]; then
  cp "${diff_file}" "${out_dir}/diff.md"
fi

if [[ -n "${artifacts_file}" && -f "${artifacts_file}" ]]; then
  cp "${artifacts_file}" "${out_dir}/artifacts.txt"
fi

PLAN_REF="${PLAN_REF:-}" APPROVAL_REF="${APPROVAL_REF:-}" MODE="${MODE:-}" ARTIFACTS_WRITTEN="${ARTIFACTS_WRITTEN:-0}" \
TENANT="${tenant}" WORKLOAD="${workload}" ENV_NAME="${env_name}" STAMP="${stamp}" OUT_DIR="${out_dir}" \
python3 - <<'PY'
import json
import os
from pathlib import Path

payload = {
    "tenant": os.environ.get("TENANT"),
    "workload": os.environ.get("WORKLOAD"),
    "env": os.environ.get("ENV_NAME"),
    "mode": os.environ.get("MODE") or "dry-run",
    "artifacts_written": os.environ.get("ARTIFACTS_WRITTEN") == "1",
    "approval_ref": os.environ.get("APPROVAL_REF"),
    "plan_ref": os.environ.get("PLAN_REF"),
    "timestamp": os.environ.get("STAMP"),
}

out_path = Path(os.environ["OUT_DIR"]) / "apply.json"
out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

bash "${FABRIC_REPO_ROOT}/ops/exposure/evidence/manifest.sh" "${out_dir}"
EXPOSURE_SIGN="${EXPOSE_SIGN:-0}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/evidence/sign.sh" "${env_name}" "${out_dir}"

echo "${out_dir}"
