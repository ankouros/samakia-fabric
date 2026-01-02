#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  apply.sh --tenant <id> --workload <id> --env <env>

Required env:
  APPROVAL_DIR or APPROVAL_PATH (approval evidence)

Execution (guarded):
  EXPOSE_EXECUTE=1 EXPOSE_REASON="..." APPROVER_ID="..."
  (prod) CHANGE_WINDOW_START, CHANGE_WINDOW_END, EXPOSE_SIGN=1, EVIDENCE_SIGN_KEY
EOT
}

tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"
approval_dir="${APPROVAL_DIR:-}"
approval_path="${APPROVAL_PATH:-}"

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
    --approval)
      approval_path="$2"
      shift 2
      ;;
    --approval-dir)
      approval_dir="$2"
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

if [[ -z "${tenant}" || -z "${workload}" || -z "${env_name}" ]]; then
  usage
  exit 2
fi

if [[ -z "${approval_path}" && -z "${approval_dir}" ]]; then
  base_dir="${FABRIC_REPO_ROOT}/evidence/exposure-approve/${tenant}/${workload}"
  if [[ -d "${base_dir}" ]]; then
    approval_dir="$(find "${base_dir}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tail -n 1)"
    if [[ -n "${approval_dir}" ]]; then
      approval_dir="${base_dir}/${approval_dir}"
    fi
  fi
fi

if [[ -n "${approval_dir}" && -z "${approval_path}" ]]; then
  if [[ -f "${approval_dir}/approval.json" ]]; then
    approval_path="${approval_dir}/approval.json"
  elif [[ -f "${approval_dir}/approval.yml" ]]; then
    approval_path="${approval_dir}/approval.yml"
  elif [[ -f "${approval_dir}/approval.yaml" ]]; then
    approval_path="${approval_dir}/approval.yaml"
  fi
fi

if [[ -z "${approval_path}" ]]; then
  echo "ERROR: approval artifact not found (set APPROVAL_DIR or APPROVAL_PATH)" >&2
  exit 1
fi

if [[ ! -f "${approval_path}" ]]; then
  echo "ERROR: approval file not found: ${approval_path}" >&2
  exit 1
fi

if [[ "${EXPOSE_EXECUTE:-0}" == "1" && "${CI:-0}" == "1" ]]; then
  echo "ERROR: exposure apply is not allowed in CI" >&2
  exit 2
fi

if [[ "${EXPOSE_EXECUTE:-0}" == "1" ]]; then
  if [[ -z "${APPROVER_ID:-}" ]]; then
    echo "ERROR: APPROVER_ID is required for execute" >&2
    exit 1
  fi
  if [[ -z "${EXPOSE_REASON:-}" ]]; then
    echo "ERROR: EXPOSE_REASON is required for execute" >&2
    exit 1
  fi
fi

approval_json="${approval_path}"
if [[ "${approval_json}" =~ \.ya?ml$ ]]; then
  approval_json="$(mktemp)"
  python3 - <<PY
import json
import yaml
from pathlib import Path

src = Path("${approval_path}")
Path("${approval_json}").write_text(json.dumps(yaml.safe_load(src.read_text()), indent=2, sort_keys=True) + "\n")
PY
fi

mapfile -t approval_fields < <(APPROVAL_JSON="${approval_json}" python3 - <<'PY'
import json
import os

approval = json.loads(open(os.environ["APPROVAL_JSON"], "r", encoding="utf-8").read())

scope = approval.get("scope", {})
approver = approval.get("approver", {})
window = approval.get("change_window", {})

print(approval.get("plan_evidence_ref", ""))
print(scope.get("env", ""))
print(scope.get("tenant", ""))
print(scope.get("workload", ""))
print(approver.get("id", ""))
print(approval.get("reason", ""))
print(window.get("start", ""))
print(window.get("end", ""))
PY
)

plan_ref="${approval_fields[0]:-}"
approval_env="${approval_fields[1]:-}"
approval_tenant="${approval_fields[2]:-}"
approval_workload="${approval_fields[3]:-}"
approval_approver_id="${approval_fields[4]:-}"
approval_reason="${approval_fields[5]:-}"
approval_window_start="${approval_fields[6]:-}"
approval_window_end="${approval_fields[7]:-}"

if [[ -z "${plan_ref}" ]]; then
  plan_ref="${PLAN_EVIDENCE_REF:-}"
fi

if [[ -z "${plan_ref}" ]]; then
  echo "ERROR: approval missing plan_evidence_ref (set PLAN_EVIDENCE_REF)" >&2
  exit 1
fi

if [[ "${approval_env}" != "${env_name}" || "${approval_tenant}" != "${tenant}" || "${approval_workload}" != "${workload}" ]]; then
  echo "ERROR: approval scope does not match target ${env_name}/${tenant}/${workload}" >&2
  exit 1
fi

if [[ "${EXPOSE_EXECUTE:-0}" == "1" ]]; then
  if [[ -n "${approval_approver_id}" && "${approval_approver_id}" != "${APPROVER_ID}" ]]; then
    echo "ERROR: approval approver_id does not match APPROVER_ID" >&2
    exit 1
  fi
  if [[ -n "${approval_reason}" && "${approval_reason}" != "${EXPOSE_REASON}" ]]; then
    echo "ERROR: approval reason does not match EXPOSE_REASON" >&2
    exit 1
  fi
fi

plan_dir="${plan_ref}"
if [[ ! "${plan_dir}" = /* ]]; then
  plan_dir="${FABRIC_REPO_ROOT}/${plan_ref}"
fi

plan_file="${plan_dir}/plan.json"
if [[ ! -f "${plan_file}" ]]; then
  echo "ERROR: plan file not found: ${plan_file}" >&2
  exit 1
fi

mapfile -t plan_scope < <(PLAN_FILE="${plan_file}" python3 - <<'PY'
import json
import os

plan = json.loads(open(os.environ["PLAN_FILE"], "r", encoding="utf-8").read())
print(plan.get("env", ""))
print(plan.get("tenant", ""))
print(plan.get("workload", ""))
PY
)

if [[ "${plan_scope[0]:-}" != "${env_name}" || "${plan_scope[1]:-}" != "${tenant}" || "${plan_scope[2]:-}" != "${workload}" ]]; then
  echo "ERROR: plan scope does not match target ${env_name}/${tenant}/${workload}" >&2
  exit 1
fi

bash "${FABRIC_REPO_ROOT}/ops/tenants/redaction.sh" "${plan_file}"
bash "${FABRIC_REPO_ROOT}/ops/tenants/redaction.sh" "${approval_json}"

APPROVAL_PATH="${approval_path}" TENANT="${tenant}" WORKLOAD="${workload}" ENV="${env_name}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/apply/validate-apply.sh"

mapfile -t plan_fields < <(PLAN_FILE="${plan_file}" python3 - <<'PY'
import json
import os

plan = json.loads(open(os.environ["PLAN_FILE"], "r", encoding="utf-8").read())
print(",".join(plan.get("providers", []) or []))
print(",".join(plan.get("variants", []) or []))
PY
)

providers="${plan_fields[0]:-}"
variants="${plan_fields[1]:-}"
if [[ -z "${providers}" || -z "${variants}" ]]; then
  echo "ERROR: plan missing providers or variants" >&2
  exit 1
fi

policy_decision="$(mktemp)"
EXPOSURE_SIGN="${EXPOSE_SIGN:-0}" CHANGE_WINDOW_START="${CHANGE_WINDOW_START:-}" CHANGE_WINDOW_END="${CHANGE_WINDOW_END:-}" \
TENANT="${tenant}" WORKLOAD="${workload}" ENV="${env_name}" PROVIDERS="${providers}" VARIANTS="${variants}" \
DECISION_OUT="${policy_decision}" POLICY_FILE="${POLICY_FILE:-${FABRIC_REPO_ROOT}/contracts/exposure/exposure-policy.yml}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/policy/evaluate.sh"

allowed=$(DECISION_FILE="${policy_decision}" python3 - <<'PY'
import json
import os

with open(os.environ["DECISION_FILE"], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print("true" if data.get("allowed") else "false")
PY
)

if [[ "${allowed}" != "true" ]]; then
  echo "ERROR: exposure policy did not allow apply" >&2
  cat "${policy_decision}" >&2 || true
  exit 1
fi

if [[ "${env_name}" == "samakia-prod" ]]; then
  if [[ -z "${CHANGE_WINDOW_START:-}" || -z "${CHANGE_WINDOW_END:-}" ]]; then
    echo "ERROR: prod apply requires CHANGE_WINDOW_START and CHANGE_WINDOW_END" >&2
    exit 1
  fi
  if [[ "${CHANGE_WINDOW_START}" != "${approval_window_start}" || "${CHANGE_WINDOW_END}" != "${approval_window_end}" ]]; then
    echo "ERROR: change window mismatch between approval and apply" >&2
    exit 1
  fi
  if [[ "${EXPOSE_SIGN:-0}" != "1" ]]; then
    echo "ERROR: prod apply requires EXPOSE_SIGN=1" >&2
    exit 1
  fi
  if [[ -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
    echo "ERROR: EVIDENCE_SIGN_KEY is required for prod signing" >&2
    exit 1
  fi
  bash "${FABRIC_REPO_ROOT}/ops/scripts/maint-window.sh" \
    --start "${CHANGE_WINDOW_START}" --end "${CHANGE_WINDOW_END}" \
    --max-minutes "${CHANGE_WINDOW_MAX_MINUTES:-60}"
fi

make -C "${FABRIC_REPO_ROOT}" bindings.render TENANT="${tenant}"
make -C "${FABRIC_REPO_ROOT}" bindings.verify.offline TENANT="${tenant}" WORKLOAD="${workload}"

mode="dry-run"
artifacts_written=0
applied_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
artifacts_list="$(mktemp)"

if [[ "${EXPOSE_EXECUTE:-0}" == "1" ]]; then
  MODE="execute" APPLIED_AT="${applied_at}" APPROVAL_REF="${approval_path}" PLAN_REF="${plan_ref}" \
    bash "${FABRIC_REPO_ROOT}/ops/exposure/apply/write-artifacts.sh" --plan "${plan_file}" >"${artifacts_list}"
  artifacts_written=1
  mode="execute"
else
  python3 - <<PY >"${artifacts_list}"
import json
plan = json.loads(open("${plan_file}").read())
for artifact in plan.get("artifacts", []) or []:
    path = artifact.get("path")
    if path:
        print(path)
PY
  echo "DRY_RUN: exposure apply for ${tenant}/${workload} (set EXPOSE_EXECUTE=1 to apply)"
fi

apply_decision="$(mktemp)"
MODE="${mode}" APPROVAL_REF="${approval_path}" PLAN_REF="${plan_ref}" APPROVER_ID="${APPROVER_ID:-${approval_approver_id}}" \
EXPOSE_REASON="${EXPOSE_REASON:-${approval_reason}}" POLICY_DECISION="${policy_decision}" STAMP="${applied_at}" \
APPLY_DECISION="${apply_decision}" \
python3 - <<'PY'
import json
import os
from pathlib import Path

policy = json.loads(Path(os.environ["POLICY_DECISION"]).read_text())

payload = {
    "allowed": policy.get("allowed"),
    "reason_codes": policy.get("reason_codes"),
    "required_guards": policy.get("required_guards"),
    "policy_version": policy.get("policy_version"),
    "mode": os.environ.get("MODE"),
    "approval_ref": os.environ.get("APPROVAL_REF"),
    "plan_ref": os.environ.get("PLAN_REF"),
    "approver_id": os.environ.get("APPROVER_ID"),
    "reason": os.environ.get("EXPOSE_REASON"),
    "timestamp": os.environ.get("STAMP"),
}

Path(os.environ["APPLY_DECISION"]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

diff_file="$(mktemp)"
bash "${FABRIC_REPO_ROOT}/ops/exposure/plan/diff.sh" --plan "${plan_file}" --out "${diff_file}"

evidence_dir=$(EVIDENCE_STAMP="${applied_at}" MODE="${mode}" PLAN_REF="${plan_ref}" APPROVAL_REF="${approval_path}" \
  ARTIFACTS_WRITTEN="${artifacts_written}" EXPOSE_SIGN="${EXPOSE_SIGN:-0}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/apply/evidence.sh" \
    --tenant "${tenant}" --workload "${workload}" --env "${env_name}" \
    --plan "${plan_file}" --approval "${approval_json}" --decision "${apply_decision}" \
    --diff "${diff_file}" --artifacts "${artifacts_list}")

echo "PASS apply: evidence -> ${evidence_dir}"

rm -f "${policy_decision}" "${diff_file}" "${apply_decision}" "${artifacts_list}"
if [[ "${approval_json}" != "${approval_path}" ]]; then
  rm -f "${approval_json}"
fi
