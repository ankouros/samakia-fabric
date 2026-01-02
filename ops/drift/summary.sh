#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

TENANT="${TENANT:-}"
if [[ -z "${TENANT}" ]]; then
  echo "ERROR: TENANT is required (use TENANT=all for all tenants with evidence)" >&2
  exit 2
fi

DRIFT_EVIDENCE_ROOT="${DRIFT_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/drift}"
DRIFT_SUMMARY_ROOT="${DRIFT_SUMMARY_ROOT:-${FABRIC_REPO_ROOT}/artifacts/tenant-status}"

usage() {
  echo "usage: drift/summary.sh TENANT=<id|all>" >&2
}

if [[ "${TENANT}" == "--help" || "${TENANT}" == "-h" ]]; then
  usage
  exit 0
fi

emit_summary() {
  local tenant="$1"
  local base_dir="${DRIFT_EVIDENCE_ROOT}/${tenant}"
  if [[ ! -d "${base_dir}" ]]; then
    echo "ERROR: no drift evidence found for tenant ${tenant}" >&2
    return 2
  fi

  local latest
  latest="$(find "${base_dir}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tail -n 1)"
  if [[ -z "${latest}" ]]; then
    echo "ERROR: no drift runs present for tenant ${tenant}" >&2
    return 2
  fi

  local classification="${base_dir}/${latest}/classification.json"
  if [[ ! -f "${classification}" ]]; then
    echo "ERROR: classification.json missing for tenant ${tenant}" >&2
    return 2
  fi

  local out_dir="${DRIFT_SUMMARY_ROOT}/${tenant}"
  mkdir -p "${out_dir}"

  local summary_json="${out_dir}/drift-summary.json"
  local summary_md="${out_dir}/drift-summary.md"

  python3 - "${classification}" "${summary_json}" "${summary_md}" "${tenant}" "${latest}" <<'PY'
import json
import sys
from pathlib import Path

classification_path = Path(sys.argv[1])
summary_json = Path(sys.argv[2])
summary_md = Path(sys.argv[3])
tenant = sys.argv[4]
run_id = sys.argv[5]

payload = json.loads(classification_path.read_text())
signals = payload.get("signals", [])

tenant_signals = [s for s in signals if s.get("owner") == "tenant"]
operator_signals = [s for s in signals if s.get("owner") == "operator"]

severity_rank = {"info": 0, "warn": 1, "critical": 2}

def compute_overall(signals_list):
    if not signals_list:
        return {"severity": "info", "status": "PASS", "class": "none"}
    max_signal = max(signals_list, key=lambda s: severity_rank.get(s.get("severity", "info"), 0))
    return {
        "severity": max_signal.get("severity", "info"),
        "status": max_signal.get("status", "PASS"),
        "class": max_signal.get("class", "unknown"),
    }

tenant_overall = compute_overall(tenant_signals)
operator_present = bool(operator_signals)

summary_payload = {
    "tenant": tenant,
    "timestamp": payload.get("timestamp"),
    "run_id": run_id,
    "overall": tenant_overall,
    "tenant_signals": tenant_signals,
    "operator_signals_present": operator_present,
}

summary_json.write_text(json.dumps(summary_payload, indent=2, sort_keys=True) + "\n")

lines = [
    "# Tenant Drift Summary",
    "",
    f"Tenant: {tenant}",
    f"Timestamp (UTC): {payload.get('timestamp')}",
    f"Run: {run_id}",
    "",
    f"Overall: {tenant_overall.get('severity')} ({tenant_overall.get('status')})",
]

if tenant_signals:
    lines.append("")
    lines.append("Tenant-visible signals:")
    for signal in tenant_signals:
        lines.append(
            f"- {signal.get('severity')} {signal.get('class')}: {signal.get('summary')}"
        )

if operator_present:
    lines.append("")
    lines.append("Operator-only signals are present. Contact the operator team for details.")

summary_md.write_text("\n".join(lines) + "\n")
PY
  echo "PASS: tenant drift summary written to ${summary_md}"
}

if [[ "${TENANT}" == "all" ]]; then
  mapfile -t tenants < <(find "${DRIFT_EVIDENCE_ROOT}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
  if [[ "${#tenants[@]}" -eq 0 ]]; then
    echo "ERROR: no drift evidence found to summarize" >&2
    exit 2
  fi
  for tenant_id in "${tenants[@]}"; do
    emit_summary "${tenant_id}"
  done
  exit 0
fi

emit_summary "${TENANT}"
