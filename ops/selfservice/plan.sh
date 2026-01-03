#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


proposal_id="${PROPOSAL_ID:-}"
file_override="${FILE:-}"

resolve_file() {
  local id="$1"
  local file="$2"
  if [[ -n "${file}" ]]; then
    printf '%s' "${file}"
    return
  fi
  if [[ -z "${id}" ]]; then
    echo ""; return
  fi
  local inbox
  inbox=$(find "${FABRIC_REPO_ROOT}/selfservice/inbox" -type f -name "proposal.yml" -path "*/${id}/*" 2>/dev/null | head -n1 || true)
  if [[ -n "${inbox}" ]]; then
    printf '%s' "${inbox}"
    return
  fi
  if [[ -f "${FABRIC_REPO_ROOT}/examples/selfservice/${id}.yml" ]]; then
    printf '%s' "${FABRIC_REPO_ROOT}/examples/selfservice/${id}.yml"
    return
  fi
  echo ""
}

proposal_path="$(resolve_file "${proposal_id}" "${file_override}")"
if [[ -z "${proposal_path}" || ! -f "${proposal_path}" ]]; then
  echo "ERROR: proposal file not found" >&2
  exit 1
fi

# Guard against execute flags in plan-only mode.
guarded_flags=(
  EXPOSE_EXECUTE
  EXPOSE_APPLY
  APPLY_EXECUTE
  ROLLBACK_EXECUTE
  VERIFY_LIVE
  MATERIALIZE_EXECUTE
  ROTATE_EXECUTE
  BIND_EXECUTE
  PROPOSAL_APPLY
)
for flag in "${guarded_flags[@]}"; do
  if [[ "${!flag:-0}" == "1" ]]; then
    echo "ERROR: plan-only mode; ${flag}=1 is not allowed" >&2
    exit 2
  fi
done

mapfile -t plan_info < <(PROPOSAL_PATH="${proposal_path}" python3 - <<'PY'
import os
import yaml
from pathlib import Path
proposal = yaml.safe_load(Path(os.environ["PROPOSAL_PATH"]).read_text())
changes = proposal.get("desired_changes", []) if isinstance(proposal, dict) else []

tenant_id = proposal.get("tenant_id", "")
proposal_id = proposal.get("proposal_id", "")
target_env = proposal.get("target_env", "")

binding_needed = any(isinstance(c, dict) and c.get("kind") == "binding" for c in changes)
capacity_needed = any(isinstance(c, dict) and c.get("kind") == "capacity" for c in changes)
workloads = []
for change in changes:
    if not isinstance(change, dict):
        continue
    if change.get("kind") == "exposure_request":
        exposure = change.get("exposure", {}) if isinstance(change.get("exposure"), dict) else {}
        workload = exposure.get("workload")
        if workload:
            workloads.append(workload)

print(tenant_id)
print(proposal_id)
print(target_env)
print("1" if binding_needed else "0")
print("1" if capacity_needed else "0")
print(",".join(sorted(set(workloads))))
PY
)

tenant_id="${plan_info[0]:-}"
proposal_id="${plan_info[1]:-}"
target_env="${plan_info[2]:-}"
binding_flag="${plan_info[3]:-0}"
capacity_flag="${plan_info[4]:-0}"
workload_list="${plan_info[5]:-}"

if [[ -z "${tenant_id}" || -z "${proposal_id}" ]]; then
  echo "ERROR: proposal missing tenant_id or proposal_id" >&2
  exit 1
fi

evidence_dir="${FABRIC_REPO_ROOT}/evidence/selfservice/${tenant_id}/${proposal_id}"
mkdir -p "${evidence_dir}"

if [[ "${SKIP_VALIDATE:-0}" != "1" ]]; then
  VALIDATION_OUT="${evidence_dir}/validation.json" FILE="${proposal_path}" \
    bash "${FABRIC_REPO_ROOT}/ops/selfservice/validate.sh"
fi

binding_status="SKIP"
binding_command=""
if [[ "${binding_flag}" == "1" ]]; then
  binding_command="make bindings.validate"
  if make -C "${FABRIC_REPO_ROOT}" bindings.validate; then
    binding_status="PASS"
  else
    binding_status="FAIL"
  fi
fi

capacity_status="SKIP"
if [[ "${capacity_flag}" == "1" ]]; then
  if make -C "${FABRIC_REPO_ROOT}" tenants.capacity.validate TENANT="${tenant_id}"; then
    capacity_status="PASS"
  else
    capacity_status="FAIL"
  fi
fi

exposure_results_file="$(mktemp)"
printf '[]' >"${exposure_results_file}"

IFS=',' read -r -a workloads <<<"${workload_list}"
exposure_status="SKIP"
for workload in "${workloads[@]}"; do
  if [[ -z "${workload}" ]]; then
    continue
  fi
  exposure_status="PASS"
  output=""
  status="PASS"
  evidence_path=""
  if output=$(TENANT="${tenant_id}" WORKLOAD="${workload}" ENV="${target_env}" \
    bash "${FABRIC_REPO_ROOT}/ops/exposure/plan/plan.sh" 2>&1); then
    evidence_path=$(printf '%s\n' "${output}" | awk '/PASS plan: evidence ->/ {print $NF}' | tail -n 1)
  else
    status="FAIL"
  fi
  python3 - "${exposure_results_file}" "${workload}" "${status}" "${evidence_path}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
workload = sys.argv[2]
status = sys.argv[3]
evidence = sys.argv[4]

payload = json.loads(path.read_text())
payload.append({
    "workload": workload,
    "status": status,
    "evidence_dir": evidence or None,
})
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
  if [[ "${status}" != "PASS" ]]; then
    exposure_status="FAIL"
  fi
  if [[ "${status}" == "FAIL" ]]; then
    echo "ERROR: exposure plan failed for workload ${workload}" >&2
  fi
done

plan_out="${evidence_dir}/plan.json"
POLICY_ENV="${target_env}" BINDING_STATUS="${binding_status}" BINDING_COMMAND="${binding_command}" \
  CAPACITY_STATUS="${capacity_status}" EXPOSURE_RESULTS_FILE="${exposure_results_file}" \
  PROPOSAL_PATH="${proposal_path}" PLAN_OUT="${plan_out}" python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path
import yaml

proposal_path = Path(os.environ["PROPOSAL_PATH"])
plan_out = Path(os.environ["PLAN_OUT"])

proposal = yaml.safe_load(proposal_path.read_text())
policy_env = os.environ.get("POLICY_ENV", "")

exposure_results_file = Path(os.environ["EXPOSURE_RESULTS_FILE"])
exposure_results = json.loads(exposure_results_file.read_text()) if exposure_results_file.exists() else []

approvals_required = True
change_window_required = "prod" in policy_env
signing_required = "prod" in policy_env

plan = {
    "proposal_id": proposal.get("proposal_id"),
    "tenant_id": proposal.get("tenant_id"),
    "target_env": proposal.get("target_env"),
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "binding_plan": {
        "status": os.environ.get("BINDING_STATUS"),
        "command": os.environ.get("BINDING_COMMAND"),
    },
    "capacity_plan": {
        "status": os.environ.get("CAPACITY_STATUS"),
        "command": "make tenants.capacity.validate TENANT=<tenant>",
    },
    "exposure_plan": exposure_results,
    "policy_requirements": {
        "approvals_required": approvals_required,
        "change_window_required": change_window_required,
        "signing_required": signing_required,
    },
}

plan_out.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
PY

rm -f "${exposure_results_file}"

printf 'OK: plan generated at %s\n' "${plan_out}"

if [[ "${binding_status}" == "FAIL" || "${capacity_status}" == "FAIL" || "${exposure_status}" == "FAIL" ]]; then
  exit 1
fi
