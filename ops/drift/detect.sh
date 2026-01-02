#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

TENANT="${TENANT:-}"
if [[ -z "${TENANT}" ]]; then
  echo "ERROR: TENANT is required (use TENANT=all for all tenants)" >&2
  exit 2
fi

DRIFT_OFFLINE="${DRIFT_OFFLINE:-1}"
DRIFT_FAIL_ON="${DRIFT_FAIL_ON:-none}"
DRIFT_NON_BLOCKING="${DRIFT_NON_BLOCKING:-0}"
DRIFT_REQUIRE_SIGN="${DRIFT_REQUIRE_SIGN:-auto}"
DRIFT_EVIDENCE_ROOT="${DRIFT_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/drift}"
DRIFT_SUMMARY_ROOT="${DRIFT_SUMMARY_ROOT:-${FABRIC_REPO_ROOT}/artifacts/tenant-status}"

usage() {
  cat <<'EOF_USAGE' >&2
usage: drift/detect.sh TENANT=<id|all>

Optional env:
  DRIFT_OFFLINE=1            # default; use local evidence only
  DRIFT_FAIL_ON=none|warn|critical
  DRIFT_NON_BLOCKING=1       # always exit 0 (still emits evidence)
  DRIFT_REQUIRE_SIGN=auto|0|1
  DRIFT_EVIDENCE_ROOT=...     # override evidence output root
  DRIFT_SUMMARY_ROOT=...      # override tenant summary output root
EOF_USAGE
}

if [[ "${TENANT}" == "--help" || "${TENANT}" == "-h" ]]; then
  usage
  exit 0
fi

require_sign=0
if [[ "${DRIFT_REQUIRE_SIGN}" == "1" ]]; then
  require_sign=1
elif [[ "${DRIFT_REQUIRE_SIGN}" == "auto" ]]; then
  if [[ "${ENV:-}" == *prod* || "${ENV:-}" == "prod" ]]; then
    require_sign=1
  fi
fi

if [[ "${require_sign}" -eq 1 && "${EVIDENCE_SIGN:-0}" != "1" ]]; then
  echo "ERROR: EVIDENCE_SIGN=1 required for drift evidence in prod or when DRIFT_REQUIRE_SIGN=1" >&2
  exit 2
fi

mapfile -t tenants < <(python3 - <<'PY'
import os
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])
tenants = set()
for path in root.glob("contracts/tenants/**/tenant.yml"):
    parts = path.parts
    if "_schema" in parts or "_templates" in parts:
        continue
    tenants.add(path.parent.name)
print("\n".join(sorted(tenants)))
PY
)

if [[ "${TENANT}" != "all" ]]; then
  tenants=("${TENANT}")
fi

if [[ "${#tenants[@]}" -eq 0 ]]; then
  echo "ERROR: no tenants found to process" >&2
  exit 2
fi

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/evidence.sh"

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

overall_fail=0

run_compare() {
  local tenant="$1"
  local script="$2"
  local out_file="$3"
  local name="$4"

  set +e
  local output
  output=$(TENANT="${tenant}" bash "${script}" 2>&1)
  local rc=$?
  set -e

  if [[ ${rc} -ne 0 ]]; then
    python3 - <<PY
import json
print(json.dumps({"tenant": "${tenant}", "status": "UNKNOWN", "issues": ["${name} compare failed"]}, indent=2, sort_keys=True))
PY
  else
    printf '%s\n' "${output}"
  fi >"${out_file}"
}

for tenant_id in "${tenants[@]}"; do
  run_dir="${DRIFT_EVIDENCE_ROOT}/${tenant_id}/${stamp}"
  mkdir -p "${run_dir}"

  tmp_dir="$(mktemp -d)"
  declared_raw="${tmp_dir}/declared.json"
  observed_raw="${tmp_dir}/observed.json"
  diff_raw="${tmp_dir}/diff.json"

  python3 - <<PY
import json
import os
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])
tenant = "${tenant_id}"

bindings_dir = root / "contracts" / "bindings" / "tenants" / tenant
render_dir = root / "artifacts" / "bindings" / tenant
capacity_contract = root / "contracts" / "tenants" / tenant / "capacity.yml"
if not capacity_contract.exists():
    capacity_contract = root / "contracts" / "tenants" / "examples" / tenant / "capacity.yml"

bindings = sorted([str(p.relative_to(root)) for p in bindings_dir.glob("*.binding.yml")]) if bindings_dir.exists() else []
renders = sorted([str(p.relative_to(root)) for p in render_dir.glob("*/connection.json")]) if render_dir.exists() else []

payload = {
    "tenant": tenant,
    "bindings": bindings,
    "renders": renders,
    "capacity_contract": str(capacity_contract.relative_to(root)) if capacity_contract.exists() else None,
}

Path("${declared_raw}").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

  python3 - <<PY
import json
import os
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])
tenant = "${tenant_id}"

verify_root = root / "evidence" / "bindings-verify" / tenant
observe_root = root / "evidence" / "tenants" / tenant


def latest_dir(path: Path):
    if not path.exists():
        return None
    runs = sorted([p for p in path.iterdir() if p.is_dir()])
    return runs[-1] if runs else None

observed = {"tenant": tenant, "bindings_verify": None, "substrate_observe": None}

latest_verify = latest_dir(verify_root)
if latest_verify:
    results_path = latest_verify / "results.json"
    if results_path.exists():
        try:
            payload = json.loads(results_path.read_text())
        except json.JSONDecodeError:
            payload = []
        observed["bindings_verify"] = {
            "run_id": latest_verify.name,
            "results_count": len(payload),
        }
    else:
        observed["bindings_verify"] = {"run_id": latest_verify.name, "results_count": 0}

latest_observe = latest_dir(observe_root)
if latest_observe:
    obs_path = latest_observe / "substrate-observe" / "observed.json"
    if obs_path.exists():
        try:
            obs_payload = json.loads(obs_path.read_text())
        except json.JSONDecodeError:
            obs_payload = {}
        observed["substrate_observe"] = {
            "run_id": latest_observe.name,
            "providers": obs_payload.get("providers", []),
            "observations_count": len(obs_payload.get("observations", [])),
        }

Path("${observed_raw}").write_text(json.dumps(observed, indent=2, sort_keys=True) + "\n")
PY

  bindings_json="${tmp_dir}/bindings.json"
  capacity_json="${tmp_dir}/capacity.json"
  security_json="${tmp_dir}/security.json"
  availability_json="${tmp_dir}/availability.json"

  run_compare "${tenant_id}" "${FABRIC_REPO_ROOT}/ops/drift/compare/bindings.sh" "${bindings_json}" "bindings"
  run_compare "${tenant_id}" "${FABRIC_REPO_ROOT}/ops/drift/compare/capacity.sh" "${capacity_json}" "capacity"
  run_compare "${tenant_id}" "${FABRIC_REPO_ROOT}/ops/drift/compare/security.sh" "${security_json}" "security"
  run_compare "${tenant_id}" "${FABRIC_REPO_ROOT}/ops/drift/compare/availability.sh" "${availability_json}" "availability"

  python3 - <<PY
import json
from pathlib import Path

bindings = json.loads(Path("${bindings_json}").read_text())
capacity = json.loads(Path("${capacity_json}").read_text())
security = json.loads(Path("${security_json}").read_text())
availability = json.loads(Path("${availability_json}").read_text())

payload = {
    "tenant": "${tenant_id}",
    "bindings": bindings,
    "capacity": capacity,
    "security": security,
    "availability": availability,
}

Path("${diff_raw}").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

  bash "${FABRIC_REPO_ROOT}/ops/drift/redact.sh" "${declared_raw}" "${run_dir}/declared.json"
  bash "${FABRIC_REPO_ROOT}/ops/drift/redact.sh" "${observed_raw}" "${run_dir}/observed.json"
  bash "${FABRIC_REPO_ROOT}/ops/drift/redact.sh" "${diff_raw}" "${run_dir}/diff.json"

  bash "${FABRIC_REPO_ROOT}/ops/drift/classify.sh" --input "${run_dir}/diff.json" --output "${run_dir}/classification.json" --tenant "${tenant_id}"

  python3 - <<PY
import json
from pathlib import Path

classification = json.loads(Path("${run_dir}/classification.json").read_text())
summary_lines = [
    "# Drift Summary",
    "",
    f"Tenant: {classification.get('tenant')}",
    f"Timestamp (UTC): {classification.get('timestamp')}",
    "",
    f"Overall: {classification.get('overall', {}).get('severity')} ({classification.get('overall', {}).get('status')})",
    "",
    "Signals:",
]
for signal in classification.get("signals", []):
    summary_lines.append(
        f"- {signal.get('severity')} {signal.get('class')} ({signal.get('owner')}): {signal.get('summary')}"
    )

Path("${run_dir}/summary.md").write_text("\n".join(summary_lines) + "\n")
PY

  write_metadata "${run_dir}" "${tenant_id}" "drift" "${stamp}"
  write_manifest "${run_dir}"

  if [[ "${EVIDENCE_SIGN:-0}" == "1" || "${require_sign}" -eq 1 ]]; then
    EVIDENCE_SIGN=1 bash "${FABRIC_REPO_ROOT}/ops/substrate/common/signer.sh" "${run_dir}"
  fi

  TENANT="${tenant_id}" DRIFT_SUMMARY_ROOT="${DRIFT_SUMMARY_ROOT}" bash "${FABRIC_REPO_ROOT}/ops/drift/summary.sh"

  severity="$(python3 - <<PY
import json
from pathlib import Path
payload = json.loads(Path("${run_dir}/classification.json").read_text())
print(payload.get("overall", {}).get("severity", "info"))
PY
)"

  case "${DRIFT_FAIL_ON}" in
    none)
      ;;
    warn)
      if [[ "${severity}" == "warn" || "${severity}" == "critical" ]]; then
        overall_fail=1
      fi
      ;;
    critical)
      if [[ "${severity}" == "critical" ]]; then
        overall_fail=1
      fi
      ;;
    *)
      echo "ERROR: invalid DRIFT_FAIL_ON value: ${DRIFT_FAIL_ON}" >&2
      exit 2
      ;;
  esac

  rm -rf "${tmp_dir}"

done

if [[ "${DRIFT_NON_BLOCKING}" == "1" ]]; then
  echo "WARN: drift detection completed in non-blocking mode"
  exit 0
fi

if [[ "${overall_fail}" -eq 1 ]]; then
  echo "WARN: drift classification exceeded threshold (${DRIFT_FAIL_ON})" >&2
  exit 2
fi

exit 0
