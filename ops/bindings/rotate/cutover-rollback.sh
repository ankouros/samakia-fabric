#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

usage() {
  cat >&2 <<'EOT'
Usage:
  cutover-rollback.sh --file <cutover.yml> --evidence <dir>

Environment:
  ROLLBACK_EXECUTE=1       (required)
  ROTATE_REASON="..."     (required)
  VERIFY_LIVE=1            (required for live verification)
  EVIDENCE_SIGN=1 EVIDENCE_SIGN_KEY=<id> (required for prod)
EOT
}

file="${FILE:-}"
evidence_dir="${CUTOVER_EVIDENCE_DIR:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      file="$2"
      shift 2
      ;;
    --evidence)
      evidence_dir="$2"
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

if [[ -z "${file}" || -z "${evidence_dir}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${file}" ]]; then
  echo "ERROR: cutover file not found: ${file}" >&2
  exit 2
fi

if [[ ! -d "${evidence_dir}" ]]; then
  echo "ERROR: evidence dir not found: ${evidence_dir}" >&2
  exit 2
fi

if [[ "${ROLLBACK_EXECUTE:-0}" != "1" ]]; then
  echo "ERROR: set ROLLBACK_EXECUTE=1 to run rollback" >&2
  exit 2
fi

if [[ -z "${ROTATE_REASON:-}" ]]; then
  echo "ERROR: ROTATE_REASON is required" >&2
  exit 2
fi

if [[ "${CI:-0}" == "1" ]]; then
  echo "ERROR: cutover rollback is not allowed in CI" >&2
  exit 2
fi

cutover_json="$(bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-validate.sh" --file "${file}")"

read -r tenant env workload verify_mode secrets_backend < <(python3 - <<'PY' "${cutover_json}"
import json
import sys
payload = json.loads(sys.argv[1])
print(
    payload.get("tenant", ""),
    payload.get("env", ""),
    payload.get("workload_id", ""),
    payload.get("verify_mode", ""),
    payload.get("secrets_backend", ""),
)
PY
)

if [[ -z "${tenant}" || -z "${workload}" ]]; then
  echo "ERROR: cutover metadata missing tenant/workload_id" >&2
  exit 2
fi

is_prod="0"
if [[ "${env}" == "prod" || "${env}" == "samakia-prod" ]]; then
  is_prod="1"
fi

change_window_start=""
change_window_end=""
change_window_id=""
read -r change_window_start change_window_end change_window_id < <(python3 - <<'PY' "${cutover_json}"
import json
import sys
payload = json.loads(sys.argv[1])
window = payload.get("change_window") or {}
print(window.get("start", ""), window.get("end", ""), window.get("id", ""))
PY
)

if [[ "${is_prod}" == "1" ]]; then
  if [[ -z "${change_window_start}" || -z "${change_window_end}" ]]; then
    echo "ERROR: prod cutover requires change_window.start and change_window.end" >&2
    exit 2
  fi
  if [[ "${EVIDENCE_SIGN:-0}" != "1" || -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
    echo "ERROR: prod rollback requires EVIDENCE_SIGN=1 and EVIDENCE_SIGN_KEY" >&2
    exit 2
  fi
  MAINT_WINDOW_START="${change_window_start}" MAINT_WINDOW_END="${change_window_end}" \
    bash "${FABRIC_REPO_ROOT}/ops/tenants/execute/change-window.sh"
fi

backup_dir="${evidence_dir}/backup"
if [[ ! -d "${backup_dir}" ]]; then
  echo "ERROR: backup not found in evidence dir: ${backup_dir}" >&2
  exit 2
fi

mapfile -t backup_files < <(cd "${backup_dir}" && find . -type f -print | sort)
if [[ ${#backup_files[@]} -eq 0 ]]; then
  echo "ERROR: backup directory is empty: ${backup_dir}" >&2
  exit 2
fi

for rel_path in "${backup_files[@]}"; do
  rel_path="${rel_path#./}"
  src="${backup_dir}/${rel_path}"
  dest="${FABRIC_REPO_ROOT}/${rel_path}"
  mkdir -p "$(dirname "${dest}")"
  cp "${src}" "${dest}"
done

mapfile -t binding_rows < <(python3 - <<'PY' "${cutover_json}" "${FABRIC_REPO_ROOT}"
import json
import sys
from pathlib import Path

payload = json.loads(sys.argv[1])
root = Path(sys.argv[2]).resolve()

for rel in payload.get("bindings", []):
    path = (root / rel).resolve()
    print(f"{rel}\t{path}")
PY
)

for row in "${binding_rows[@]}"; do
  abs="${row#*$'\t'}"
  bash "${FABRIC_REPO_ROOT}/ops/bindings/render/render-connection-manifest.sh" --binding "${abs}"
done

verify_status="PASS"
verify_message="ok"
verify_mode_resolved="offline"

if [[ "${verify_mode}" == "live" ]]; then
  verify_mode_resolved="live"
  if [[ "${VERIFY_LIVE:-0}" != "1" ]]; then
    verify_status="FAIL"
    verify_message="VERIFY_LIVE=1 required for live verification"
  fi
fi

if [[ "${verify_status}" == "PASS" ]]; then
  if ! VERIFY_MODE="${verify_mode_resolved}" VERIFY_LIVE="${VERIFY_LIVE:-0}" \
    TENANT="${tenant}" WORKLOAD="${workload}" BIND_SECRETS_BACKEND="${secrets_backend:-}" \
    bash "${FABRIC_REPO_ROOT}/ops/bindings/verify/verify.sh"; then
    verify_status="FAIL"
    verify_message="verification failed"
  fi
fi

python3 - <<'PY' "${cutover_json}" "${evidence_dir}" "${ROTATE_REASON}" "${ROLLBACK_EXECUTE}" "${verify_mode_resolved}" "${verify_status}" "${verify_message}" "${change_window_start}" "${change_window_end}" "${change_window_id}"
import json
import sys
from pathlib import Path

cutover = json.loads(sys.argv[1])
out_dir = Path(sys.argv[2])

payload = {
    "tenant": cutover.get("tenant"),
    "env": cutover.get("env"),
    "workload_id": cutover.get("workload_id"),
    "mode": "rollback",
    "rollback_execute": sys.argv[4],
    "rotate_reason": sys.argv[3],
    "verify_mode": sys.argv[5],
    "verify_status": sys.argv[6],
    "verify_message": sys.argv[7],
    "change_window": {
        "start": sys.argv[8],
        "end": sys.argv[9],
        "id": sys.argv[10],
    },
    "old_secret_ref": cutover.get("old_secret_ref"),
    "new_secret_ref": cutover.get("new_secret_ref"),
    "bindings": cutover.get("bindings", []),
    "secrets_backend": cutover.get("secrets_backend"),
}
(out_dir / "rollback.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-evidence.sh" "${evidence_dir}"

echo "PASS cutover rollback evidence -> ${evidence_dir}"

if [[ "${verify_status}" != "PASS" ]]; then
  echo "ERROR: rollback verification failed" >&2
  exit 2
fi
