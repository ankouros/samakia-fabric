#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  approve.sh --tenant <id> --workload <id> --env <env>

Optional env:
  APPROVER_ID, APPROVER_NAME, APPROVER_ROLE
  EXPOSE_REASON or APPROVAL_REASON
  PLAN_EVIDENCE_REF
  CHANGE_WINDOW_START, CHANGE_WINDOW_END, CHANGE_WINDOW_ID
  EXPOSE_SIGN=1 (prod requires signing)
  EVIDENCE_SIGN_KEY (for GPG signing)
  APPROVAL_INPUT=<path> (YAML/JSON approval template)
  APPROVAL_ALLOW_CI=1 (allow approvals in CI)
EOT
}

tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"
approver_id="${APPROVER_ID:-}"
approver_name="${APPROVER_NAME:-}"
approver_role="${APPROVER_ROLE:-}"
reason="${EXPOSE_REASON:-${APPROVAL_REASON:-}}"
plan_ref="${PLAN_EVIDENCE_REF:-}"
proposal_id="${PROPOSAL_ID:-}"
approval_input="${APPROVAL_INPUT:-}"
window_id="${CHANGE_WINDOW_ID:-}"

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
    --input)
      approval_input="$2"
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
  echo "ERROR: exposure approval is not allowed in CI (set APPROVAL_ALLOW_CI=1 to override)" >&2
  exit 2
fi

if [[ -z "${tenant}" || -z "${workload}" || -z "${env_name}" ]]; then
  usage
  exit 2
fi

if [[ -z "${approver_id}" && -z "${approval_input}" ]]; then
  echo "ERROR: APPROVER_ID is required (or provide APPROVAL_INPUT)" >&2
  exit 1
fi

if [[ -z "${reason}" && -z "${approval_input}" ]]; then
  echo "ERROR: EXPOSE_REASON or APPROVAL_REASON is required (or provide APPROVAL_INPUT)" >&2
  exit 1
fi

if [[ -z "${plan_ref}" && -z "${approval_input}" ]]; then
  echo "ERROR: PLAN_EVIDENCE_REF is required (or provide APPROVAL_INPUT)" >&2
  exit 1
fi

if [[ "${env_name}" == "samakia-prod" ]]; then
  if [[ -z "${CHANGE_WINDOW_START:-}" || -z "${CHANGE_WINDOW_END:-}" ]]; then
    echo "ERROR: prod approval requires CHANGE_WINDOW_START and CHANGE_WINDOW_END" >&2
    exit 1
  fi
  if [[ "${EXPOSE_SIGN:-0}" != "1" ]]; then
    echo "ERROR: prod approval requires EXPOSE_SIGN=1" >&2
    exit 1
  fi
  if [[ -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
    echo "ERROR: EVIDENCE_SIGN_KEY is required for prod approval signing" >&2
    exit 1
  fi
fi

stamp="${EVIDENCE_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
out_dir="${APPROVAL_EVIDENCE_DIR:-${FABRIC_REPO_ROOT}/evidence/exposure-approve/${tenant}/${workload}/${stamp}}"

APPROVAL_INPUT="${approval_input}" TENANT="${tenant}" WORKLOAD="${workload}" ENV_NAME="${env_name}" \
APPROVER_ID="${approver_id}" APPROVER_NAME="${approver_name}" APPROVER_ROLE="${approver_role}" \
APPROVAL_REASON="${reason}" PLAN_REF="${plan_ref}" PROPOSAL_ID="${proposal_id}" \
CHANGE_WINDOW_START="${CHANGE_WINDOW_START:-}" CHANGE_WINDOW_END="${CHANGE_WINDOW_END:-}" CHANGE_WINDOW_ID="${window_id}" \
EXPOSE_SIGN="${EXPOSE_SIGN:-0}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" STAMP="${stamp}" OUT_DIR="${out_dir}" \
python3 - <<'PY'
import json
import os
from pathlib import Path

author_input = os.environ.get("APPROVAL_INPUT")

tenant = os.environ["TENANT"]
workload = os.environ["WORKLOAD"]
env_name = os.environ["ENV_NAME"]
approver_id = os.environ.get("APPROVER_ID")
approver_name = os.environ.get("APPROVER_NAME")
approver_role = os.environ.get("APPROVER_ROLE")
reason = os.environ.get("APPROVAL_REASON")
plan_ref = os.environ.get("PLAN_REF")
proposal_id = os.environ.get("PROPOSAL_ID")

window_start = os.environ.get("CHANGE_WINDOW_START")
window_end = os.environ.get("CHANGE_WINDOW_END")
window_id = os.environ.get("CHANGE_WINDOW_ID")

signature_ref = None
if os.environ.get("EXPOSE_SIGN") == "1":
    key = os.environ.get("EVIDENCE_SIGN_KEY")
    if key:
        signature_ref = f"gpg:{key}"

stamp = os.environ["STAMP"]
out_dir = Path(os.environ["OUT_DIR"])

payload = {}
if author_input:
    src = Path(author_input)
    if not src.exists():
        raise SystemExit(f"ERROR: approval input not found: {src}")
    if src.suffix in {".yml", ".yaml"}:
        import yaml
        payload = yaml.safe_load(src.read_text()) or {}
    else:
        payload = json.loads(src.read_text())

payload.setdefault("apiVersion", "v1alpha1")
payload.setdefault("kind", "ExposureApproval")
if proposal_id and not payload.get("proposal_id"):
    payload["proposal_id"] = proposal_id
if plan_ref and not payload.get("plan_evidence_ref"):
    payload["plan_evidence_ref"] = plan_ref

payload.setdefault("scope", {})
payload["scope"].setdefault("env", env_name)
payload["scope"].setdefault("tenant", tenant)
payload["scope"].setdefault("workload", workload)

payload.setdefault("approver", {})
if approver_id:
    payload["approver"].setdefault("id", approver_id)
if approver_name:
    payload["approver"].setdefault("name", approver_name)
if approver_role:
    payload["approver"].setdefault("role", approver_role)

payload.setdefault("approved_at", stamp)
if reason:
    payload.setdefault("reason", reason)

if window_start or window_end or window_id:
    payload.setdefault("change_window", {})
    if window_id:
        payload["change_window"].setdefault("window_id", window_id)
    if window_start:
        payload["change_window"].setdefault("start", window_start)
    if window_end:
        payload["change_window"].setdefault("end", window_end)

if signature_ref:
    payload.setdefault("signature_ref", signature_ref)

out_dir.mkdir(parents=True, exist_ok=True)
approval_path = out_dir / "approval.json"
approval_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")

decision = {
    "status": "approved",
    "tenant": tenant,
    "workload": workload,
    "env": env_name,
    "approver_id": approver_id or payload.get("approver", {}).get("id"),
    "reason": reason or payload.get("reason"),
    "approval_ref": str(approval_path),
    "timestamp": stamp,
}
(out_dir / "decision.json").write_text(json.dumps(decision, indent=2, sort_keys=True) + "\n")
PY

bash "${FABRIC_REPO_ROOT}/ops/tenants/redaction.sh" "${out_dir}/approval.json"

bash "${FABRIC_REPO_ROOT}/ops/exposure/evidence/manifest.sh" "${out_dir}"
EXPOSURE_SIGN="${EXPOSE_SIGN:-0}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/evidence/sign.sh" "${env_name}" "${out_dir}"

bash "${FABRIC_REPO_ROOT}/ops/exposure/approve/validate-approval.sh" --approval "${out_dir}/approval.json"

echo "${out_dir}"
