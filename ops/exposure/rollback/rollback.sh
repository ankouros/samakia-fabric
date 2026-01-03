#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  echo "usage: rollback.sh --tenant <id> --workload <id> --env <env>" >&2
}

tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"

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

requested_by="${ROLLBACK_REQUESTED_BY:-${APPROVER_ID:-}}"
if [[ -z "${requested_by}" ]]; then
  echo "ERROR: set ROLLBACK_REQUESTED_BY or APPROVER_ID" >&2
  exit 1
fi

TENANT="${tenant}" WORKLOAD="${workload}" ENV="${env_name}" \
  ROLLBACK_EXECUTE="${ROLLBACK_EXECUTE:-0}" ROLLBACK_REASON="${ROLLBACK_REASON:-}" \
  CHANGE_WINDOW_START="${CHANGE_WINDOW_START:-}" CHANGE_WINDOW_END="${CHANGE_WINDOW_END:-}" \
  EXPOSE_SIGN="${EXPOSE_SIGN:-0}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/rollback/validate-rollback.sh"

if [[ "${env_name}" == "samakia-prod" ]]; then
  bash "${FABRIC_REPO_ROOT}/ops/scripts/maint-window.sh" \
    --start "${CHANGE_WINDOW_START}" --end "${CHANGE_WINDOW_END}" \
    --max-minutes "${CHANGE_WINDOW_MAX_MINUTES:-60}"
fi

artifact_root="${FABRIC_REPO_ROOT}/artifacts/exposure/${env_name}/${tenant}/${workload}"
mode="dry-run"
artifacts_removed=0

if [[ "${ROLLBACK_EXECUTE:-0}" == "1" ]]; then
  if [[ -d "${artifact_root}" ]]; then
    rm -rf "${artifact_root}"
  fi
  artifacts_removed=1
  mode="execute"
else
  echo "DRY_RUN: rollback for ${tenant}/${workload} (set ROLLBACK_EXECUTE=1 to execute)"
fi

make -C "${FABRIC_REPO_ROOT}" bindings.verify.offline TENANT="${tenant}" WORKLOAD="${workload}"

postcheck_json="$(mktemp)"
drift_json="$(mktemp)"
rollback_json="$(mktemp)"
decision_json="$(mktemp)"

bash "${FABRIC_REPO_ROOT}/ops/exposure/verify/postcheck.sh" \
  --tenant "${tenant}" --workload "${workload}" --env "${env_name}" --out "${postcheck_json}"

EXPOSE_SIGN="${EXPOSE_SIGN:-0}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/verify/drift-snapshot.sh" \
  --tenant "${tenant}" --env "${env_name}" --out "${drift_json}"

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
evidence_ref="evidence/exposure-rollback/${tenant}/${workload}/${stamp}"

TENANT="${tenant}" WORKLOAD="${workload}" ENV_NAME="${env_name}" REQUESTED_BY="${requested_by}" \
ROLLBACK_REASON="${ROLLBACK_REASON:-}" STAMP="${stamp}" EVIDENCE_REF="${evidence_ref}" ROLLBACK_JSON="${rollback_json}" \
python3 - <<'PY'
import json
import os
from pathlib import Path

payload = {
    "apiVersion": "v1alpha1",
    "kind": "ExposureRollback",
    "scope": {
        "env": os.environ["ENV_NAME"],
        "tenant": os.environ["TENANT"],
        "workload": os.environ["WORKLOAD"],
    },
    "intent": {
        "action": "disable_exposure_artifacts",
        "notes": "rollback removes exposure artifacts only",
    },
    "verification": {
        "steps": [
            "exposure artifacts removed",
            "bindings verify offline",
            "drift snapshot captured",
        ],
        "evidence_ref": os.environ["EVIDENCE_REF"],
    },
    "requested_by": os.environ["REQUESTED_BY"],
    "requested_at": os.environ["STAMP"],
    "reason": os.environ.get("ROLLBACK_REASON") or "",
}

Path(os.environ["ROLLBACK_JSON"]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

ROLLBACK_JSON="${rollback_json}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

payload = json.loads(Path(os.environ["ROLLBACK_JSON"]).read_text())
if not payload.get("reason"):
    print("ERROR: rollback reason missing", file=sys.stderr)
    sys.exit(1)
PY

MODE="${mode}" ARTIFACTS_REMOVED="${artifacts_removed}" POSTCHECK_JSON="${postcheck_json}" DRIFT_JSON="${drift_json}" \
STAMP="${stamp}" DECISION_JSON="${decision_json}" python3 - <<'PY'
import json
import os
from pathlib import Path

postcheck = json.loads(Path(os.environ["POSTCHECK_JSON"]).read_text())

payload = {
    "mode": os.environ.get("MODE"),
    "artifacts_removed": os.environ.get("ARTIFACTS_REMOVED") == "1",
    "postcheck_status": postcheck.get("status"),
    "drift_ref": json.loads(Path(os.environ["DRIFT_JSON"]).read_text()).get("snapshot_dir"),
    "timestamp": os.environ.get("STAMP"),
}

Path(os.environ["DECISION_JSON"]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

postcheck_status="$(python3 - <<PY
import json
print(json.loads(open("${postcheck_json}", "r", encoding="utf-8").read()).get("status", "unknown"))
PY
)"
if [[ "${mode}" == "execute" && "${postcheck_status}" != "not_exposed" ]]; then
  echo "ERROR: rollback postcheck did not return to baseline (status=${postcheck_status})" >&2
  exit 1
fi

evidence_dir=$(EVIDENCE_STAMP="${stamp}" EXPOSE_SIGN="${EXPOSE_SIGN:-0}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/rollback/evidence.sh" \
    --tenant "${tenant}" --workload "${workload}" --env "${env_name}" \
    --rollback "${rollback_json}" --drift "${drift_json}" --decision "${decision_json}" \
    --postcheck "${postcheck_json}")

echo "PASS rollback: evidence -> ${evidence_dir}"

rm -f "${postcheck_json}" "${drift_json}" "${rollback_json}" "${decision_json}"
