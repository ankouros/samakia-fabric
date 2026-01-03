#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  reject.sh --tenant <id> --workload <id> --env <env>

Optional env:
  APPROVER_ID, APPROVER_NAME, APPROVER_ROLE
  REJECT_REASON or EXPOSE_REASON
  PLAN_EVIDENCE_REF
  APPROVAL_ALLOW_CI=1 (allow rejects in CI)
EOT
}

tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"
approver_id="${APPROVER_ID:-}"
approver_name="${APPROVER_NAME:-}"
approver_role="${APPROVER_ROLE:-}"
reason="${REJECT_REASON:-${EXPOSE_REASON:-}}"
plan_ref="${PLAN_EVIDENCE_REF:-}"

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
      plan_ref="$2"
      shift 2
      ;;
    --approver-id)
      approver_id="$2"
      shift 2
      ;;
    --reason)
      reason="$2"
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

if [[ "${CI:-0}" == "1" && "${APPROVAL_ALLOW_CI:-0}" != "1" ]]; then
  echo "ERROR: exposure rejection is not allowed in CI (set APPROVAL_ALLOW_CI=1 to override)" >&2
  exit 2
fi

if [[ -z "${tenant}" || -z "${workload}" || -z "${env_name}" ]]; then
  usage
  exit 2
fi

if [[ -z "${approver_id}" ]]; then
  echo "ERROR: APPROVER_ID is required" >&2
  exit 1
fi

if [[ -z "${reason}" ]]; then
  echo "ERROR: REJECT_REASON is required" >&2
  exit 1
fi

stamp="${EVIDENCE_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
out_dir="${APPROVAL_EVIDENCE_DIR:-${FABRIC_REPO_ROOT}/evidence/exposure-approve/${tenant}/${workload}/${stamp}}"

TENANT="${tenant}" WORKLOAD="${workload}" ENV_NAME="${env_name}" \
APPROVER_ID="${approver_id}" APPROVER_NAME="${approver_name}" APPROVER_ROLE="${approver_role}" \
REASON="${reason}" PLAN_REF="${plan_ref}" STAMP="${stamp}" OUT_DIR="${out_dir}" \
python3 - <<'PY'
import json
import os
from pathlib import Path

tenant = os.environ["TENANT"]
workload = os.environ["WORKLOAD"]
env_name = os.environ["ENV_NAME"]
approver_id = os.environ.get("APPROVER_ID")
approver_name = os.environ.get("APPROVER_NAME")
approver_role = os.environ.get("APPROVER_ROLE")
reason = os.environ.get("REASON")
plan_ref = os.environ.get("PLAN_REF")
stamp = os.environ["STAMP"]

out_dir = Path(os.environ["OUT_DIR"])
out_dir.mkdir(parents=True, exist_ok=True)

rejection = {
    "apiVersion": "v1alpha1",
    "kind": "ExposureRejection",
    "scope": {"env": env_name, "tenant": tenant, "workload": workload},
    "approver": {"id": approver_id, "name": approver_name, "role": approver_role},
    "rejected_at": stamp,
    "reason": reason,
}
if plan_ref:
    rejection["plan_evidence_ref"] = plan_ref

(out_dir / "rejection.json").write_text(json.dumps(rejection, indent=2, sort_keys=True) + "\n")

decision = {
    "status": "rejected",
    "tenant": tenant,
    "workload": workload,
    "env": env_name,
    "approver_id": approver_id,
    "reason": reason,
    "rejection_ref": str(out_dir / "rejection.json"),
    "timestamp": stamp,
}
(out_dir / "decision.json").write_text(json.dumps(decision, indent=2, sort_keys=True) + "\n")
PY

bash "${FABRIC_REPO_ROOT}/ops/tenants/redaction.sh" "${out_dir}/rejection.json"

bash "${FABRIC_REPO_ROOT}/ops/exposure/evidence/manifest.sh" "${out_dir}"
EXPOSURE_SIGN="${EXPOSE_SIGN:-0}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/evidence/sign.sh" "${env_name}" "${out_dir}"

echo "${out_dir}"
