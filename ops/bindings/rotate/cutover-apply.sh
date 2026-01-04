#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

usage() {
  cat >&2 <<'EOT'
Usage:
  cutover-apply.sh --file <cutover.yml>

Environment:
  ROTATE_EXECUTE=1          (required)
  CUTOVER_EXECUTE=1         (required)
  ROTATE_REASON="..."       (required)
  VERIFY_LIVE=1             (required for live verification)
  BIND_SECRETS_BACKEND=...  (default: vault)
  EVIDENCE_SIGN=1 EVIDENCE_SIGN_KEY=<id> (required for prod)
EOT
}

file="${FILE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      file="$2"
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

if [[ -z "${file}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${file}" ]]; then
  echo "ERROR: cutover file not found: ${file}" >&2
  exit 2
fi

if [[ "${ROTATE_EXECUTE:-0}" != "1" ]]; then
  echo "ERROR: set ROTATE_EXECUTE=1 to apply cutover" >&2
  exit 2
fi

if [[ "${CUTOVER_EXECUTE:-0}" != "1" ]]; then
  echo "ERROR: set CUTOVER_EXECUTE=1 to apply cutover" >&2
  exit 2
fi

if [[ -z "${ROTATE_REASON:-}" ]]; then
  echo "ERROR: ROTATE_REASON is required" >&2
  exit 2
fi

if [[ "${CI:-0}" == "1" ]]; then
  echo "ERROR: cutover apply is not allowed in CI" >&2
  exit 2
fi

cutover_json="$(bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-validate.sh" --file "${file}")"

read -r tenant env workload verify_mode old_ref new_ref secrets_backend < <(python3 - <<'PY' "${cutover_json}"
import json
import sys
payload = json.loads(sys.argv[1])
print(
    payload.get("tenant", ""),
    payload.get("env", ""),
    payload.get("workload_id", ""),
    payload.get("verify_mode", ""),
    payload.get("old_secret_ref", ""),
    payload.get("new_secret_ref", ""),
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
    echo "ERROR: prod cutover requires EVIDENCE_SIGN=1 and EVIDENCE_SIGN_KEY" >&2
    exit 2
  fi
  MAINT_WINDOW_START="${change_window_start}" MAINT_WINDOW_END="${change_window_end}" \
    bash "${FABRIC_REPO_ROOT}/ops/tenants/execute/change-window.sh"
fi

stamp="${CUTOVER_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
base_dir="${FABRIC_REPO_ROOT}/evidence/rotation/${tenant}/${workload}/${stamp}"
backup_dir="${base_dir}/backup"
mkdir -p "${backup_dir}"

bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/redact.sh" --in "${file}" --out "${base_dir}/cutover.yml.redacted"

bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-plan.sh" \
  --file "${file}" --out "${base_dir}/plan.json" --diff "${base_dir}/diff.md"

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

if [[ ${#binding_rows[@]} -eq 0 ]]; then
  echo "ERROR: no bindings found in cutover file" >&2
  exit 2
fi

backup_index="${base_dir}/backup.json"
{
  echo '{'
  echo '  "bindings": ['
  first=1
  for row in "${binding_rows[@]}"; do
    rel="${row%%$'\t'*}"
    abs="${row#*$'\t'}"
    if [[ ! -f "${abs}" ]]; then
      echo "ERROR: binding file missing: ${rel}" >&2
      exit 2
    fi
    dest="${backup_dir}/${rel}"
    mkdir -p "$(dirname "${dest}")"
    cp "${abs}" "${dest}"
    if [[ "${first}" -eq 0 ]]; then
      echo ','
    fi
    first=0
    printf '    {"binding": "%s", "backup": "%s"}' "${rel}" "backup/${rel}"
  done
  echo
  echo '  ]'
  echo '}'
} > "${backup_index}"

for row in "${binding_rows[@]}"; do
  rel="${row%%$'\t'*}"
  abs="${row#*$'\t'}"
  python3 - <<'PY' "${abs}" "${old_ref}" "${new_ref}"
from pathlib import Path
import sys

path = Path(sys.argv[1])
old_ref = sys.argv[2]
new_ref = sys.argv[3]

lines = path.read_text().splitlines()
updated = []
changed = False
for line in lines:
    if "secret_ref" in line and old_ref in line:
        updated.append(line.replace(old_ref, new_ref))
        changed = True
    else:
        updated.append(line)

if not changed:
    raise SystemExit(f"ERROR: old secret_ref not found in {path}")

path.write_text("\n".join(updated) + "\n")
PY

  bash "${FABRIC_REPO_ROOT}/ops/bindings/render/render-connection-manifest.sh" --binding "${abs}"
done

python3 - <<'PY' "${cutover_json}" "${base_dir}" "${ROTATE_REASON}" "${ROTATE_EXECUTE}" "${CUTOVER_EXECUTE}" "${VERIFY_LIVE:-0}" "${EVIDENCE_SIGN:-0}" "${EVIDENCE_SIGN_KEY:-}" "${change_window_start}" "${change_window_end}" "${change_window_id}"
import json
import sys
from pathlib import Path

cutover = json.loads(sys.argv[1])
out_dir = Path(sys.argv[2])

payload = {
    "tenant": cutover.get("tenant"),
    "env": cutover.get("env"),
    "workload_id": cutover.get("workload_id"),
    "mode": "execute",
    "rotate_execute": sys.argv[4],
    "cutover_execute": sys.argv[5],
    "rotate_reason": sys.argv[3],
    "verify_mode": cutover.get("verify_mode"),
    "verify_live": sys.argv[6],
    "evidence_sign": sys.argv[7],
    "evidence_sign_key": sys.argv[8],
    "change_window": {
        "start": sys.argv[9],
        "end": sys.argv[10],
        "id": sys.argv[11],
    },
    "old_secret_ref": cutover.get("old_secret_ref"),
    "new_secret_ref": cutover.get("new_secret_ref"),
    "bindings": cutover.get("bindings", []),
    "secrets_backend": cutover.get("secrets_backend"),
}
(out_dir / "decision.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

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

verify_cmd=(
  "${FABRIC_REPO_ROOT}/ops/bindings/verify/verify.sh"
)

if [[ "${verify_status}" == "PASS" ]]; then
  if ! VERIFY_MODE="${verify_mode_resolved}" VERIFY_LIVE="${VERIFY_LIVE:-0}" \
    TENANT="${tenant}" WORKLOAD="${workload}" BIND_SECRETS_BACKEND="${secrets_backend:-}" \
    "${verify_cmd[@]}"; then
    verify_status="FAIL"
    verify_message="verification failed"
  fi
fi

python3 - <<'PY' "${base_dir}" "${verify_mode_resolved}" "${verify_status}" "${verify_message}"
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
verify = {
    "mode": sys.argv[2],
    "status": sys.argv[3],
    "message": sys.argv[4],
}
(out_dir / "verify.json").write_text(json.dumps(verify, indent=2, sort_keys=True) + "\n")
PY

bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-evidence.sh" "${base_dir}"

echo "PASS cutover evidence -> ${base_dir}"

if [[ "${verify_status}" != "PASS" ]]; then
  echo "ERROR: cutover verification failed" >&2
  echo "Suggested rollback:" >&2
  echo "ROLLBACK_EXECUTE=1 ROTATE_REASON=\"${ROTATE_REASON}\" CUTOVER_EVIDENCE_DIR=\"${base_dir}\" \\" >&2
  echo "  make rotation.cutover.rollback FILE=${file}" >&2
  exit 2
fi
