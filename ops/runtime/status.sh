#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

TENANT="${TENANT:-}"
WORKLOAD="${WORKLOAD:-}"

if [[ -z "${TENANT}" ]]; then
  echo "ERROR: TENANT is required (use TENANT=all for all SLO contracts)" >&2
  exit 2
fi

EVIDENCE_ROOT="${RUNTIME_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/runtime-eval}"
STATUS_ROOT="${RUNTIME_STATUS_ROOT:-${FABRIC_REPO_ROOT}/artifacts/runtime-status}"
SLO_ROOT="${SLO_ROOT:-${FABRIC_REPO_ROOT}/contracts/tenants}"
SLO_EXAMPLES_ROOT="${SLO_EXAMPLES_ROOT:-${FABRIC_REPO_ROOT}/contracts/tenants/examples}"

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

for slo_file in "${slo_files[@]}"; do
  read -r tenant workload provider owner < <(parse_slo "${slo_file}")

  if [[ "${TENANT}" != "all" && "${tenant}" != "${TENANT}" ]]; then
    continue
  fi

  evidence_base="${EVIDENCE_ROOT}/${tenant}/${workload}"
  if [[ ! -d "${evidence_base}" ]]; then
    echo "WARN: no runtime evidence found for ${tenant}/${workload}" >&2
    continue
  fi

  latest="$(find "${evidence_base}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tail -n 1)"
  if [[ -z "${latest}" ]]; then
    echo "WARN: no runtime runs found for ${tenant}/${workload}" >&2
    continue
  fi

  classification_path="${evidence_base}/${latest}/classification.json"
  if [[ ! -f "${classification_path}" ]]; then
    echo "WARN: classification.json missing for ${tenant}/${workload}" >&2
    continue
  fi

  status_dir="${STATUS_ROOT}/${tenant}/${workload}"
  mkdir -p "${status_dir}"
  status_json="${status_dir}/status.json"
  status_md="${status_dir}/status.md"

  python3 - "${classification_path}" "${status_json}" "${status_md}" "${provider}" "${owner}" <<'PY'
import json
import sys
from pathlib import Path

classification_path = Path(sys.argv[1])
status_json_path = Path(sys.argv[2])
status_md_path = Path(sys.argv[3])
provider = sys.argv[4]
owner = sys.argv[5]

payload = json.loads(classification_path.read_text())
classification = payload.get("classification", "UNKNOWN")
reasons = payload.get("reasons", [])

next_action = {
    "INFRA_FAULT": "Investigate substrate reachability and TLS failures.",
    "DRIFT": "Review drift evidence and confirm intended state.",
    "SLO_VIOLATION": "Review metrics and notify the SLO owner.",
    "OK": "No action required.",
}.get(classification, "No action required.")

status = {
    "tenant": payload.get("tenant"),
    "workload": payload.get("workload"),
    "provider": provider,
    "owner": owner,
    "timestamp_utc": payload.get("timestamp_utc"),
    "classification": classification,
    "reasons": reasons,
    "next_action": next_action,
}

status_json_path.write_text(json.dumps(status, indent=2, sort_keys=True) + "\n")

lines = [
    "# Runtime Status",
    "",
    f"Tenant: {status.get('tenant')}",
    f"Workload: {status.get('workload')}",
    f"Owner: {owner}",
    f"Timestamp (UTC): {status.get('timestamp_utc')}",
    "",
    f"Classification: {classification}",
    f"Next action (informational only): {next_action}",
]
if reasons:
    lines.append("")
    lines.append("Reasons:")
    for reason in reasons:
        lines.append(f"- {reason}")
status_md_path.write_text("\n".join(lines) + "\n")
PY

  echo "PASS: runtime status updated at ${status_md}"

done
