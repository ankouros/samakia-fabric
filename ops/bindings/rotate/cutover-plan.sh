#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

usage() {
  cat >&2 <<'EOT'
Usage:
  cutover-plan.sh --file <cutover.yml> [--out <plan.json> --diff <diff.md>]
  cutover-plan.sh --file <cutover.yml> [--out-dir <dir>] [--emit-evidence]

Notes:
  - Read-only: no binding updates.
  - Generates plan.json + diff.md for the cutover.
  - --emit-evidence writes cutover.yml.redacted + decision/verify stubs + manifest.
EOT
}

file="${FILE:-}"
out=""
diff=""
out_dir=""
emit_evidence="0"
stamp=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      file="$2"
      shift 2
      ;;
    --out)
      out="$2"
      shift 2
      ;;
    --diff)
      diff="$2"
      shift 2
      ;;
    --out-dir)
      out_dir="$2"
      shift 2
      ;;
    --emit-evidence)
      emit_evidence="1"
      shift
      ;;
    --stamp)
      stamp="$2"
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

cutover_json="$(bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-validate.sh" --file "${file}")"

read -r tenant workload < <(python3 - <<'PY' "${cutover_json}"
import json
import sys
payload = json.loads(sys.argv[1])
meta = {
    "tenant": payload.get("tenant", ""),
    "workload_id": payload.get("workload_id", ""),
}
print(meta["tenant"], meta["workload_id"])
PY
)

if [[ -z "${out}" || -z "${diff}" ]]; then
  if [[ -z "${out_dir}" ]]; then
    stamp="${stamp:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    if [[ -z "${tenant}" || -z "${workload}" ]]; then
      echo "ERROR: cutover metadata missing tenant/workload_id" >&2
      exit 2
    fi
    out_dir="${FABRIC_REPO_ROOT}/evidence/rotation/${tenant}/${workload}/${stamp}"
  fi
  out="${out_dir}/plan.json"
  diff="${out_dir}/diff.md"
fi

mkdir -p "$(dirname "${out}")" "$(dirname "${diff}")"

PLAN_OUT="${out}" DIFF_OUT="${diff}" CUTOVER_JSON="${cutover_json}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" python3 - <<'PY'
import json
import os
from pathlib import Path
from datetime import datetime, timezone

plan_out = Path(os.environ["PLAN_OUT"])
diff_out = Path(os.environ["DIFF_OUT"])
repo_root = Path(os.environ["FABRIC_REPO_ROOT"]).resolve()
cutover = json.loads(os.environ["CUTOVER_JSON"])

old_ref = cutover.get("old_secret_ref")
new_ref = cutover.get("new_secret_ref")
bindings = cutover.get("bindings", [])

changes = []
for rel_path in bindings:
    path = (repo_root / rel_path).resolve()
    content = path.read_text() if path.exists() else ""
    count = content.count(old_ref) if old_ref else 0
    changes.append({
        "binding": rel_path,
        "occurrences": count,
        "old_secret_ref": old_ref,
        "new_secret_ref": new_ref,
    })

plan = {
    "kind": "binding-secret-cutover-plan",
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "cutover": cutover,
    "changes": changes,
}
plan_out.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")

lines = [
    "# Binding Secret Cutover Plan",
    "",
    f"Tenant: {cutover.get('tenant')}",
    f"Env: {cutover.get('env')}",
    f"Workload: {cutover.get('workload_id')}",
    f"Verify mode: {cutover.get('verify_mode')}",
    "",
    "Planned updates:",
]
for change in changes:
    lines.append(
        f"- {change['binding']}: {old_ref} -> {new_ref} (occurrences: {change['occurrences']})"
    )

lines.append("")
lines.append("Notes: plan-only; no binding files are modified.")

diff_out.write_text("\n".join(lines) + "\n")
PY

if [[ "${emit_evidence}" == "1" ]]; then
  if [[ -z "${out_dir}" ]]; then
    out_dir="$(dirname "${out}")"
  fi
  if [[ ! -d "${out_dir}" ]]; then
    mkdir -p "${out_dir}"
  fi

  bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/redact.sh" --in "${file}" --out "${out_dir}/cutover.yml.redacted"

  python3 - <<'PY' "${cutover_json}" "${out_dir}"
import json
import sys
from pathlib import Path

cutover = json.loads(sys.argv[1])
out_dir = Path(sys.argv[2])

out_dir.mkdir(parents=True, exist_ok=True)

decision = {
    "tenant": cutover.get("tenant"),
    "env": cutover.get("env"),
    "workload_id": cutover.get("workload_id"),
    "mode": "plan",
    "verify_mode": cutover.get("verify_mode"),
    "change_window": cutover.get("change_window"),
    "old_secret_ref": cutover.get("old_secret_ref"),
    "new_secret_ref": cutover.get("new_secret_ref"),
    "bindings": cutover.get("bindings", []),
}
(out_dir / "decision.json").write_text(json.dumps(decision, indent=2, sort_keys=True) + "\n")

verify = {
    "mode": cutover.get("verify_mode"),
    "status": "SKIPPED",
    "message": "plan-only; verification not executed",
}
(out_dir / "verify.json").write_text(json.dumps(verify, indent=2, sort_keys=True) + "\n")
PY

  bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-evidence.sh" "${out_dir}"
  echo "PASS cutover plan evidence -> ${out_dir}"
fi

printf '%s\n' "${out}"
