#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

TENANT="${TENANT:-}"
WORKLOAD="${WORKLOAD:-}"

if [[ -z "${TENANT}" ]]; then
  echo "ERROR: TENANT is required (use TENANT=all for all SLO contracts)" >&2
  exit 2
fi

SLO_ROOT="${SLO_ROOT:-${FABRIC_REPO_ROOT}/contracts/tenants}"
SLO_EXAMPLES_ROOT="${SLO_EXAMPLES_ROOT:-${FABRIC_REPO_ROOT}/contracts/tenants/examples}"
OBSERVATION_PATH="${OBSERVATION_PATH:-${FABRIC_REPO_ROOT}/contracts/runtime-observation/observation.yml}"
METRICS_ROOT="${SLO_METRICS_ROOT:-${FABRIC_REPO_ROOT}/artifacts/slo-metrics}"
EVIDENCE_ROOT="${SLO_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/slo}"
STATUS_ROOT="${SLO_STATUS_ROOT:-${FABRIC_REPO_ROOT}/artifacts/slo-status}"

stamp="${SLO_EVAL_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"

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

for slo_file in "${slo_files[@]}"; do
  read -r tenant workload provider owner < <(parse_slo "${slo_file}")

  if [[ "${TENANT}" != "all" && "${tenant}" != "${TENANT}" ]]; then
    continue
  fi

  packet_dir="${EVIDENCE_ROOT}/${tenant}/${workload}/${stamp}"
  inputs_dir="${packet_dir}/inputs"
  mkdir -p "${inputs_dir}"

  SLO_PATH="${slo_file}" OUT_PATH="${tmpdir}/slo.json" "${FABRIC_REPO_ROOT}/ops/runtime/load/slo.sh"
  IN_PATH="${tmpdir}/slo.json" OUT_PATH="${inputs_dir}/slo.yml" "${FABRIC_REPO_ROOT}/ops/slo/redact.sh"

  metrics_source="${METRICS_ROOT}/${tenant}/${workload}/metrics.json"
  IN_PATH="${metrics_source}" OUT_PATH="${tmpdir}/metrics.json" OBSERVATION_PATH="${OBSERVATION_PATH}" \
    "${FABRIC_REPO_ROOT}/ops/slo/normalize.sh"
  IN_PATH="${tmpdir}/metrics.json" OUT_PATH="${inputs_dir}/metrics.json" "${FABRIC_REPO_ROOT}/ops/slo/redact.sh"

  SLO_PATH="${tmpdir}/slo.json" METRICS_PATH="${tmpdir}/metrics.json" OUT_PATH="${inputs_dir}/windows.json" \
    "${FABRIC_REPO_ROOT}/ops/slo/windows.sh"

  SLO_PATH="${tmpdir}/slo.json" METRICS_PATH="${tmpdir}/metrics.json" OUT_PATH="${packet_dir}/error_budget.json" \
    "${FABRIC_REPO_ROOT}/ops/slo/error-budget.sh"

  evaluation_json="${packet_dir}/evaluation.json"
  state_json="${packet_dir}/state.json"
  summary_md="${packet_dir}/summary.md"

  status_dir="${STATUS_ROOT}/${tenant}/${workload}"
  status_json="${status_dir}/status.json"
  status_md="${status_dir}/status.md"
  mkdir -p "${status_dir}"

  python3 - "${evaluation_json}" "${state_json}" "${summary_md}" "${status_json}" "${status_md}" \
    "${tmpdir}/slo.json" "${inputs_dir}/metrics.json" "${inputs_dir}/windows.json" "${packet_dir}/error_budget.json" \
    "${tenant}" "${workload}" "${provider}" "${owner}" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

evaluation_path = Path(sys.argv[1])
state_path = Path(sys.argv[2])
summary_path = Path(sys.argv[3])
status_json_path = Path(sys.argv[4])
status_md_path = Path(sys.argv[5])
slo_path = Path(sys.argv[6])
metrics_path = Path(sys.argv[7])
windows_path = Path(sys.argv[8])
budget_path = Path(sys.argv[9])
tenant = sys.argv[10]
workload = sys.argv[11]
provider = sys.argv[12]
owner = sys.argv[13]

slo = json.loads(slo_path.read_text())
metrics = json.loads(metrics_path.read_text())
windows = json.loads(windows_path.read_text())
error_budget = json.loads(budget_path.read_text())

severity = slo.get("spec", {}).get("severity", {})
warn_threshold = severity.get("warn", 1.0)
critical_threshold = severity.get("critical", 2.0)

if not isinstance(warn_threshold, (int, float)):
    warn_threshold = 1.0
if not isinstance(critical_threshold, (int, float)):
    critical_threshold = 2.0

state_rank = {"OK": 0, "WARN": 1, "CRITICAL": 2}


def classify(record):
    notes = []
    value = record.get("value")
    breach = record.get("breach")
    burn_rate = record.get("burn_rate")
    budget_abs = record.get("budget_absolute")

    if not metrics.get("available") or value is None:
        notes.append("metrics unavailable")
        return "WARN", notes

    if budget_abs in (None, 0):
        if breach and breach > 0:
            notes.append("error budget exhausted")
            return "CRITICAL", notes
        return "OK", notes

    if breach is not None and breach >= budget_abs:
        notes.append("error budget exhausted")
        return "CRITICAL", notes

    if burn_rate is None:
        notes.append("burn rate unavailable")
        return "WARN", notes

    if burn_rate >= critical_threshold:
        notes.append("burn rate above critical threshold")
        return "CRITICAL", notes
    if burn_rate >= warn_threshold:
        notes.append("burn rate above warn threshold")
        return "WARN", notes

    if breach and breach > 0:
        notes.append("within error budget")

    return "OK", notes


objective_states = {}
objective_notes = {}

for key, record in error_budget.get("objectives", {}).items():
    state, notes = classify(record)
    objective_states[key] = state
    objective_notes[key] = notes

overall_state = "OK"
for state in objective_states.values():
    if state_rank[state] > state_rank[overall_state]:
        overall_state = state

missing_metrics = metrics.get("missing_metrics", []) if isinstance(metrics, dict) else []
if missing_metrics:
    if overall_state == "OK":
        overall_state = "WARN"

now = datetime.now(timezone.utc)
run_timestamp = metrics.get("timestamp_utc") or now.strftime("%Y-%m-%dT%H:%M:%SZ")

budget_remaining = error_budget.get("overall", {}).get("remaining")
budget_display = budget_remaining if budget_remaining is not None else "unknown"

next_action = {
    "OK": "No action required.",
    "WARN": "Review burn rate and notify the SLO owner if it persists.",
    "CRITICAL": "Notify the SLO owner and open an incident.",
}.get(overall_state, "No action required.")

objective_payload = {}
for key, record in error_budget.get("objectives", {}).items():
    objective_payload[key] = {
        "state": objective_states.get(key),
        "notes": objective_notes.get(key, []),
        "target": record.get("target"),
        "value": record.get("value"),
        "unit": record.get("unit"),
        "breach": record.get("breach"),
        "burn_rate": record.get("burn_rate"),
        "budget_remaining": record.get("remaining"),
        "objective_met": record.get("objective_met"),
    }

summary_lines = [
    "# SLO Evaluation Summary",
    "",
    f"Tenant: {tenant}",
    f"Workload: {workload}",
    f"Provider: {provider}",
    f"Owner: {owner}",
    f"Timestamp (UTC): {run_timestamp}",
    "",
    f"Overall state: {overall_state}",
    "",
    "Window:",
    f"- Type: {windows.get('type')}",
    f"- Duration: {windows.get('duration')}",
    f"- Start: {windows.get('window_start_utc')}",
    f"- End: {windows.get('window_end_utc')}",
]
if budget_remaining is not None:
    summary_lines.append(f"- Budget remaining: {budget_remaining}")
if missing_metrics:
    summary_lines.append("")
    summary_lines.append("Missing metrics:")
    for metric in missing_metrics:
        summary_lines.append(f"- {metric}")
summary_lines.append("")
summary_lines.append(f"Next action (informational only): {next_action}")
summary_lines.append("Alert delivery is disabled by default.")

summary_path.write_text("\n".join(summary_lines) + "\n")

state_payload = {
    "tenant": tenant,
    "workload": workload,
    "timestamp_utc": run_timestamp,
    "overall_state": overall_state,
    "objective_states": objective_states,
    "missing_metrics": missing_metrics,
    "window": windows,
}
state_path.write_text(json.dumps(state_payload, indent=2, sort_keys=True) + "\n")

status_payload = {
    "tenant": tenant,
    "workload": workload,
    "owner": owner,
    "timestamp_utc": run_timestamp,
    "overall_state": overall_state,
    "budget_remaining": budget_remaining,
    "window": {
        "type": windows.get("type"),
        "duration": windows.get("duration"),
        "start": windows.get("window_start_utc"),
        "end": windows.get("window_end_utc"),
    },
    "next_action": next_action,
}
status_json_path.write_text(json.dumps(status_payload, indent=2, sort_keys=True) + "\n")

status_lines = [
    "# SLO Status",
    "",
    f"Tenant: {tenant}",
    f"Workload: {workload}",
    f"Owner: {owner}",
    f"Timestamp (UTC): {run_timestamp}",
    "",
    f"Overall state: {overall_state}",
    f"Budget remaining: {budget_display}",
    "",
    "Window:",
    f"- Type: {windows.get('type')}",
    f"- Duration: {windows.get('duration')}",
    f"- Start: {windows.get('window_start_utc')}",
    f"- End: {windows.get('window_end_utc')}",
    "",
    f"Next action (informational only): {next_action}",
    "Alert delivery is disabled by default.",
]
status_md_path.write_text("\n".join(status_lines) + "\n")

evaluation_payload = {
    "tenant": tenant,
    "workload": workload,
    "provider": provider,
    "owner": owner,
    "timestamp_utc": run_timestamp,
    "window": windows,
    "metrics": metrics,
    "objectives": objective_payload,
    "overall_state": overall_state,
    "missing_metrics": missing_metrics,
    "next_action": next_action,
}

evaluation_path.write_text(json.dumps(evaluation_payload, indent=2, sort_keys=True) + "\n")
PY

  EVIDENCE_DIR="${packet_dir}" "${FABRIC_REPO_ROOT}/ops/slo/evidence.sh"
  echo "PASS: SLO evaluation written to ${packet_dir}"
  echo "PASS: SLO status written to ${status_dir}/status.md"

done
