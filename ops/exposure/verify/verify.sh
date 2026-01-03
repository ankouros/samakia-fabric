#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  echo "usage: verify.sh --tenant <id> --workload <id> --env <env>" >&2
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

mode="offline"
if [[ "${VERIFY_LIVE:-0}" == "1" ]]; then
  mode="live"
  if [[ "${CI:-0}" == "1" ]]; then
    echo "ERROR: live verify is not allowed in CI" >&2
    exit 2
  fi
fi

if [[ "${mode}" == "live" ]]; then
  VERIFY_LIVE=1 make -C "${FABRIC_REPO_ROOT}" bindings.verify.live TENANT="${tenant}" WORKLOAD="${workload}"
else
  make -C "${FABRIC_REPO_ROOT}" bindings.verify.offline TENANT="${tenant}" WORKLOAD="${workload}"
fi

verify_root="${FABRIC_REPO_ROOT}/evidence/bindings-verify/${tenant}"
latest_verify="$(find "${verify_root}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tail -n 1)"
if [[ -z "${latest_verify}" ]]; then
  echo "ERROR: bindings verify evidence not found for tenant ${tenant}" >&2
  exit 1
fi

verify_dir="${verify_root}/${latest_verify}"

verify_json="$(mktemp)"
postcheck_json="$(mktemp)"
drift_json="$(mktemp)"
decision_json="$(mktemp)"

VERIFY_DIR="${verify_dir}" WORKLOAD="${workload}" TENANT="${tenant}" ENV_NAME="${env_name}" MODE="${mode}" \
VERIFY_JSON="${verify_json}" python3 - <<'PY'
import json
import os
from pathlib import Path

verify_dir = Path(os.environ["VERIFY_DIR"])
workload = os.environ["WORKLOAD"]
mode = os.environ["MODE"]

detail_path = verify_dir / "per-binding" / f"{workload}.json"
status = "UNKNOWN"
if detail_path.exists():
    try:
        payload = json.loads(detail_path.read_text())
        status = payload.get("status", status)
    except json.JSONDecodeError:
        status = "UNKNOWN"

payload = {
    "tenant": os.environ["TENANT"],
    "workload": workload,
    "env": os.environ["ENV_NAME"],
    "mode": mode,
    "binding_verify_ref": str(verify_dir),
    "status": status,
}

Path(os.environ["VERIFY_JSON"]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

bash "${FABRIC_REPO_ROOT}/ops/exposure/verify/postcheck.sh" \
  --tenant "${tenant}" --workload "${workload}" --env "${env_name}" --out "${postcheck_json}"

EXPOSE_SIGN="${EXPOSE_SIGN:-0}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/verify/drift-snapshot.sh" \
  --tenant "${tenant}" --env "${env_name}" --out "${drift_json}"

VERIFY_JSON="${verify_json}" POSTCHECK_JSON="${postcheck_json}" DRIFT_JSON="${drift_json}" \
MODE="${mode}" STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)" DECISION_JSON="${decision_json}" python3 - <<'PY'
import json
import os
from pathlib import Path

verify = json.loads(Path(os.environ["VERIFY_JSON"]).read_text())
postcheck = json.loads(Path(os.environ["POSTCHECK_JSON"]).read_text())

payload = {
    "mode": os.environ.get("MODE"),
    "verify_status": verify.get("status"),
    "postcheck_status": postcheck.get("status"),
    "binding_verify_ref": verify.get("binding_verify_ref"),
    "drift_ref": json.loads(Path(os.environ["DRIFT_JSON"]).read_text()).get("snapshot_dir"),
    "timestamp": os.environ.get("STAMP"),
}

Path(os.environ["DECISION_JSON"]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

evidence_dir=$(EXPOSE_SIGN="${EXPOSE_SIGN:-0}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/verify/evidence.sh" \
    --tenant "${tenant}" --workload "${workload}" --env "${env_name}" \
    --verify "${verify_json}" --drift "${drift_json}" --decision "${decision_json}" --postcheck "${postcheck_json}")

echo "PASS verify: evidence -> ${evidence_dir}"

rm -f "${verify_json}" "${postcheck_json}" "${drift_json}" "${decision_json}"
