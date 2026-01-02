#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  echo "usage: validate-approval.sh --approval <approval.json|approval.yml|dir>" >&2
}

approval_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --approval)
      approval_path="$2"
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

if [[ -z "${approval_path}" ]]; then
  usage
  exit 2
fi

if [[ -d "${approval_path}" ]]; then
  if [[ -f "${approval_path}/approval.json" ]]; then
    approval_path="${approval_path}/approval.json"
  elif [[ -f "${approval_path}/approval.yml" ]]; then
    approval_path="${approval_path}/approval.yml"
  elif [[ -f "${approval_path}/approval.yaml" ]]; then
    approval_path="${approval_path}/approval.yaml"
  else
    echo "ERROR: approval file not found in directory: ${approval_path}" >&2
    exit 1
  fi
fi

if [[ ! -f "${approval_path}" ]]; then
  echo "ERROR: approval file not found: ${approval_path}" >&2
  exit 1
fi

schema_file="${FABRIC_REPO_ROOT}/contracts/exposure/approval.schema.json"
if [[ ! -f "${schema_file}" ]]; then
  echo "ERROR: approval schema not found: ${schema_file}" >&2
  exit 1
fi

APPROVAL_PATH="${approval_path}" SCHEMA_PATH="${schema_file}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
    import jsonschema
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for validation: {exc}")

approval_path = Path(os.environ["APPROVAL_PATH"])
schema_path = Path(os.environ["SCHEMA_PATH"])

schema = json.loads(schema_path.read_text())

if approval_path.suffix in {".yml", ".yaml"}:
    payload = yaml.safe_load(approval_path.read_text())
else:
    payload = json.loads(approval_path.read_text())

jsonschema.validate(instance=payload, schema=schema)

scope = payload.get("scope", {})
if not scope.get("env") or not scope.get("tenant") or not scope.get("workload"):
    raise SystemExit("ERROR: approval scope requires env/tenant/workload")

reason = payload.get("reason")
if not reason:
    raise SystemExit("ERROR: approval reason is required")

approved_at = payload.get("approved_at")
if not approved_at:
    raise SystemExit("ERROR: approval approved_at is required")

try:
    value = approved_at.replace("Z", "+00:00")
    datetime.fromisoformat(value).astimezone(timezone.utc)
except Exception as exc:
    raise SystemExit(f"ERROR: approval approved_at invalid: {exc}")

plan_ref = payload.get("plan_evidence_ref")
if not plan_ref:
    raise SystemExit("ERROR: approval requires plan_evidence_ref")
plan_path = Path(plan_ref)
if not plan_path.is_absolute():
    plan_path = (Path(os.environ["FABRIC_REPO_ROOT"]) / plan_ref).resolve()
if not plan_path.exists():
    raise SystemExit(f"ERROR: plan evidence ref not found: {plan_ref}")
plan_file = plan_path / "plan.json"
decision_file = plan_path / "decision.json"
if not plan_file.exists() or not decision_file.exists():
    raise SystemExit("ERROR: plan evidence missing plan.json or decision.json")
decision = json.loads(decision_file.read_text())
if decision.get("allowed") is not True:
    raise SystemExit("ERROR: plan decision is not allowed")

env_name = scope.get("env")
if env_name == "samakia-prod":
    change_window = payload.get("change_window") or {}
    if not change_window.get("start") or not change_window.get("end"):
        raise SystemExit("ERROR: prod approval requires change window start/end")
    try:
        start = change_window["start"].replace("Z", "+00:00")
        end = change_window["end"].replace("Z", "+00:00")
        start_dt = datetime.fromisoformat(start).astimezone(timezone.utc)
        end_dt = datetime.fromisoformat(end).astimezone(timezone.utc)
    except Exception as exc:
        raise SystemExit(f"ERROR: change window invalid: {exc}")
    if end_dt <= start_dt:
        raise SystemExit("ERROR: change window end must be after start")

    if not payload.get("signature_ref"):
        raise SystemExit("ERROR: prod approval requires signature_ref")

    evidence_dir = approval_path.parent
    manifest = evidence_dir / "manifest.sha256"
    signature = evidence_dir / "manifest.sha256.asc"
    if not manifest.exists():
        raise SystemExit("ERROR: prod approval requires manifest.sha256 in evidence dir")
    if not signature.exists():
        raise SystemExit("ERROR: prod approval requires signed manifest (manifest.sha256.asc)")

print(f"PASS approval schema: {approval_path}")
print("PASS approval validation")
PY
