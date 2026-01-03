#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


TENANT="${TENANT:-}"
WORKLOAD="${WORKLOAD:-}"

if [[ -z "${TENANT}" ]]; then
  echo "ERROR: TENANT is required (use TENANT=all for all SLO contracts)" >&2
  exit 2
fi

if [[ "${RUNTIME_LIVE:-0}" == "1" ]]; then
  echo "ERROR: live runtime evaluation is not allowed" >&2
  exit 2
fi

EVIDENCE_ROOT="${RUNTIME_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/runtime-eval}"
STATUS_ROOT="${RUNTIME_STATUS_ROOT:-${FABRIC_REPO_ROOT}/artifacts/runtime-status}"
SLO_ROOT="${SLO_ROOT:-${FABRIC_REPO_ROOT}/contracts/tenants}"
SLO_EXAMPLES_ROOT="${SLO_EXAMPLES_ROOT:-${FABRIC_REPO_ROOT}/contracts/tenants/examples}"

stamp="${RUNTIME_EVAL_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
run_timestamp="$("${FABRIC_REPO_ROOT}/ops/runtime/normalize/time.sh")"

collect_slo_files() {
  local tenant="$1"
  local workload="$2"
  local files=()
  if [[ "${tenant}" == "all" ]]; then
    mapfile -t files < <(find "${SLO_ROOT}" -type f -path "*/slo/*.yml" ! -path "*/examples/*" -print 2>/dev/null | sort)
    mapfile -t example_files < <(find "${SLO_EXAMPLES_ROOT}" -type f -path "*/slo/*.yml" -print 2>/dev/null | sort)
    files+=("${example_files[@]}")
  else
    if [[ -d "${SLO_ROOT}/${tenant}/slo" ]]; then
      mapfile -t files < <(find "${SLO_ROOT}/${tenant}/slo" -type f -name "*.yml" -print 2>/dev/null | sort)
    fi
    if [[ -d "${SLO_EXAMPLES_ROOT}/${tenant}/slo" ]]; then
      mapfile -t example_files < <(find "${SLO_EXAMPLES_ROOT}/${tenant}/slo" -type f -name "*.yml" -print 2>/dev/null | sort)
      files+=("${example_files[@]}")
    fi
  fi

  if [[ -n "${workload}" ]]; then
    local filtered=()
    for file in "${files[@]}"; do
      if [[ "$(basename "${file}")" == "${workload}.yml" ]]; then
        filtered+=("${file}")
      fi
    done
    files=("${filtered[@]}")
  fi

  printf '%s\n' "${files[@]}"
}

mapfile -t slo_files < <(collect_slo_files "${TENANT}" "${WORKLOAD}")

if [[ "${#slo_files[@]}" -eq 0 ]]; then
  echo "ERROR: no SLO contracts found for tenant=${TENANT} workload=${WORKLOAD:-all}" >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmpdir}" 2>/dev/null || true
}
trap cleanup EXIT

parse_slo() {
  local path="$1"
  python3 - "${path}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())

scope = data.get("spec", {}).get("scope", {})
meta = data.get("metadata", {})

tenant = scope.get("tenant") or meta.get("tenant")
workload = scope.get("workload") or meta.get("workload")
provider = scope.get("provider") or meta.get("provider")
owner = data.get("spec", {}).get("owner") or meta.get("owner") or "operator"

if not tenant or not workload or not provider:
    raise SystemExit("missing scope fields in SLO")

print("\t".join([tenant, workload, provider, owner]))
PY
}

for slo_file in "${slo_files[@]}"; do
  read -r tenant workload provider owner < <(parse_slo "${slo_file}")

  if [[ "${TENANT}" != "all" && "${tenant}" != "${TENANT}" ]]; then
    continue
  fi

  packet_dir="${EVIDENCE_ROOT}/${tenant}/${workload}/${stamp}"
  inputs_dir="${packet_dir}/inputs"
  mkdir -p "${inputs_dir}"

  SLO_PATH="${slo_file}" OUT_PATH="${inputs_dir}/slo.yml" "${FABRIC_REPO_ROOT}/ops/runtime/load/slo.sh"
  OUT_PATH="${inputs_dir}/observation.yml" "${FABRIC_REPO_ROOT}/ops/runtime/load/observation.sh"

  drift_raw="${tmpdir}/drift-${tenant}-${workload}.json"
  verify_raw="${tmpdir}/verify-${tenant}-${workload}.json"
  TENANT="${tenant}" WORKLOAD="${workload}" DRIFT_OUT="${drift_raw}" VERIFY_OUT="${verify_raw}" \
    "${FABRIC_REPO_ROOT}/ops/runtime/load/signals.sh"

  IN_PATH="${drift_raw}" OUT_PATH="${inputs_dir}/drift.json" "${FABRIC_REPO_ROOT}/ops/runtime/redact.sh"
  IN_PATH="${verify_raw}" OUT_PATH="${inputs_dir}/verify.json" "${FABRIC_REPO_ROOT}/ops/runtime/redact.sh"

  metrics_source="${METRICS_SOURCE:-}"
  if [[ -n "${METRICS_SOURCE_DIR:-}" ]]; then
    if [[ -f "${METRICS_SOURCE_DIR}/${tenant}/${workload}.json" ]]; then
      metrics_source="${METRICS_SOURCE_DIR}/${tenant}/${workload}.json"
    elif [[ -f "${METRICS_SOURCE_DIR}/${workload}.json" ]]; then
      metrics_source="${METRICS_SOURCE_DIR}/${workload}.json"
    elif [[ -f "${METRICS_SOURCE_DIR}/metrics.json" ]]; then
      metrics_source="${METRICS_SOURCE_DIR}/metrics.json"
    fi
  fi

  metrics_path="${tmpdir}/metrics-${tenant}-${workload}.json"
  OBSERVATION_PATH="${inputs_dir}/observation.yml" METRICS_SOURCE="${metrics_source}" OUT_PATH="${metrics_path}" \
    "${FABRIC_REPO_ROOT}/ops/runtime/normalize/metrics.sh"

  infra_eval="${tmpdir}/infra-${tenant}-${workload}.json"
  drift_eval="${tmpdir}/drift-${tenant}-${workload}-eval.json"
  slo_eval="${tmpdir}/slo-${tenant}-${workload}-eval.json"

  VERIFY_PATH="${inputs_dir}/verify.json" OUT_PATH="${infra_eval}" "${FABRIC_REPO_ROOT}/ops/runtime/classify/infra.sh"
  DRIFT_PATH="${inputs_dir}/drift.json" OUT_PATH="${drift_eval}" "${FABRIC_REPO_ROOT}/ops/runtime/classify/drift.sh"
  SLO_PATH="${inputs_dir}/slo.yml" METRICS_PATH="${metrics_path}" OUT_PATH="${slo_eval}" \
    "${FABRIC_REPO_ROOT}/ops/runtime/classify/slo.sh"

  evaluation_json="${packet_dir}/evaluation.json"
  classification_json="${packet_dir}/classification.json"
  summary_md="${packet_dir}/summary.md"

  status_dir="${STATUS_ROOT}/${tenant}/${workload}"
  status_json="${status_dir}/status.json"
  status_md="${status_dir}/status.md"
  mkdir -p "${status_dir}"

  python3 - "${evaluation_json}" "${classification_json}" "${summary_md}" "${status_json}" "${status_md}" \
    "${inputs_dir}" "${metrics_path}" "${infra_eval}" "${drift_eval}" "${slo_eval}" \
    "${tenant}" "${workload}" "${provider}" "${owner}" "${run_timestamp}" <<'PY'
import json
import sys
from pathlib import Path

evaluation_path = Path(sys.argv[1])
classification_path = Path(sys.argv[2])
summary_path = Path(sys.argv[3])
status_json_path = Path(sys.argv[4])
status_md_path = Path(sys.argv[5])
inputs_dir = Path(sys.argv[6])
metrics_path = Path(sys.argv[7])
infra_path = Path(sys.argv[8])
drift_path = Path(sys.argv[9])
slo_path = Path(sys.argv[10])
tenant = sys.argv[11]
workload = sys.argv[12]
provider = sys.argv[13]
owner = sys.argv[14]
timestamp = sys.argv[15]

metrics = json.loads(metrics_path.read_text())
infra = json.loads(infra_path.read_text())
drift = json.loads(drift_path.read_text())
slo = json.loads(slo_path.read_text())

classification_order = ["INFRA_FAULT", "DRIFT", "SLO_VIOLATION", "OK"]

classification = "OK"
reasons = []
if infra.get("status") == "FAIL":
    classification = "INFRA_FAULT"
    reasons = infra.get("reasons", [])
elif drift.get("status") == "FAIL":
    classification = "DRIFT"
    reasons = drift.get("reasons", [])
elif slo.get("status") == "FAIL":
    classification = "SLO_VIOLATION"
    reasons = slo.get("violations", [])

next_action = {
    "INFRA_FAULT": "Investigate substrate reachability and TLS failures.",
    "DRIFT": "Review drift evidence and confirm intended state.",
    "SLO_VIOLATION": "Review metrics and notify the SLO owner.",
    "OK": "No action required.",
}.get(classification, "No action required.")

evaluation = {
    "tenant": tenant,
    "workload": workload,
    "provider": provider,
    "owner": owner,
    "timestamp_utc": timestamp,
    "classification_order": classification_order,
    "inputs": {
        "drift": "inputs/drift.json",
        "verify": "inputs/verify.json",
        "slo": "inputs/slo.yml",
        "observation": "inputs/observation.yml",
    },
    "signals": {
        "infra": infra,
        "drift": drift,
        "slo": slo,
    },
    "metrics": metrics,
}

evaluation_path.write_text(json.dumps(evaluation, indent=2, sort_keys=True) + "\n")

classification_payload = {
    "tenant": tenant,
    "workload": workload,
    "provider": provider,
    "owner": owner,
    "timestamp_utc": timestamp,
    "classification": classification,
    "reasons": reasons,
}
classification_path.write_text(json.dumps(classification_payload, indent=2, sort_keys=True) + "\n")

summary_lines = [
    "# Runtime Evaluation Summary",
    "",
    f"Tenant: {tenant}",
    f"Workload: {workload}",
    f"Provider: {provider}",
    f"Owner: {owner}",
    f"Timestamp (UTC): {timestamp}",
    "",
    f"Classification: {classification}",
]
if reasons:
    summary_lines.append("\nReasons:")
    for reason in reasons:
        summary_lines.append(f"- {reason}")
summary_lines.append("")
summary_lines.append(f"Next action (informational only): {next_action}")
summary_path.write_text("\n".join(summary_lines) + "\n")

status_payload = {
    "tenant": tenant,
    "workload": workload,
    "provider": provider,
    "owner": owner,
    "timestamp_utc": timestamp,
    "classification": classification,
    "reasons": reasons,
    "next_action": next_action,
}
status_json_path.write_text(json.dumps(status_payload, indent=2, sort_keys=True) + "\n")

status_lines = [
    "# Runtime Status",
    "",
    f"Tenant: {tenant}",
    f"Workload: {workload}",
    f"Owner: {owner}",
    f"Timestamp (UTC): {timestamp}",
    "",
    f"Classification: {classification}",
    f"Next action (informational only): {next_action}",
]
if reasons:
    status_lines.append("")
    status_lines.append("Reasons:")
    for reason in reasons:
        status_lines.append(f"- {reason}")
status_md_path.write_text("\n".join(status_lines) + "\n")
PY

  EVIDENCE_DIR="${packet_dir}" "${FABRIC_REPO_ROOT}/ops/runtime/evidence.sh"
  echo "PASS: runtime evaluation written to ${packet_dir}"
  echo "PASS: runtime status written to ${status_dir}/status.md"

done
