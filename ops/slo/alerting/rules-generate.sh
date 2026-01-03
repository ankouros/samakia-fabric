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
ALERTS_ROOT="${SLO_ALERTS_ROOT:-${FABRIC_REPO_ROOT}/artifacts/slo-alerts}"

stamp="${SLO_ALERTS_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

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

if not tenant or not workload or not provider:
    raise SystemExit("missing scope fields in SLO")

print("\t".join([tenant, workload]))
PY
}

mapfile -t slo_files < <(collect_slo_files "${TENANT}" "${WORKLOAD}")

if [[ "${#slo_files[@]}" -eq 0 ]]; then
  echo "ERROR: no SLO contracts found for tenant=${TENANT} workload=${WORKLOAD:-all}" >&2
  exit 2
fi

for slo_file in "${slo_files[@]}"; do
  read -r tenant workload < <(parse_slo "${slo_file}")

  if [[ "${TENANT}" != "all" && "${tenant}" != "${TENANT}" ]]; then
    continue
  fi

  out_dir="${ALERTS_ROOT}/${tenant}/${workload}"
  out_path="${out_dir}/rules.yaml"
  mkdir -p "${out_dir}"

  python3 - "${slo_file}" "${out_path}" "${stamp}" <<'PY'
import json
import sys
from pathlib import Path

slo_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
stamp = sys.argv[3]

slo = json.loads(slo_path.read_text())

scope = slo.get("spec", {}).get("scope", {})
meta = slo.get("metadata", {})
tenant = scope.get("tenant") or meta.get("tenant")
workload = scope.get("workload") or meta.get("workload")
provider = scope.get("provider") or meta.get("provider")

severity = slo.get("spec", {}).get("severity", {})
warn_threshold = severity.get("warn", 1.0)
critical_threshold = severity.get("critical", 2.0)

window = slo.get("spec", {}).get("window", {})
for_interval = window.get("evaluation_interval") or window.get("duration") or "5m"

objectives = {
    "availability": slo.get("spec", {}).get("objectives", {}).get("availability", {}).get("target_percent"),
    "latency_p95": slo.get("spec", {}).get("objectives", {}).get("latency", {}).get("p95_ms"),
    "latency_p99": slo.get("spec", {}).get("objectives", {}).get("latency", {}).get("p99_ms"),
    "error_rate": slo.get("spec", {}).get("objectives", {}).get("error_rate", {}).get("max_percent"),
}

rules = []


def add_rule(objective, severity_label, threshold):
    rules.append({
        "alert": f"SLO{objective.title()}Burn{severity_label.title()}",
        "expr": (
            f"slo_error_budget_burn_rate{{tenant=\"{tenant}\",workload=\"{workload}\",objective=\"{objective}\"}} >= {threshold}"
        ),
        "for": for_interval,
        "labels": {
            "tenant": tenant,
            "workload": workload,
            "provider": provider,
            "objective": objective,
            "severity": severity_label,
            "delivery": "disabled",
        },
        "annotations": {
            "summary": f"SLO burn rate {severity_label} for {objective}",
            "description": "Alert readiness only; delivery disabled by default.",
        },
    })

for objective in objectives:
    add_rule(objective, "warn", warn_threshold)
    add_rule(objective, "critical", critical_threshold)

payload = {
    "groups": [
        {
            "name": f"slo.{tenant}.{workload}",
            "interval": for_interval,
            "rules": rules,
        }
    ],
    "metadata": {
        "generated_utc": stamp,
        "tenant": tenant,
        "workload": workload,
        "provider": provider,
        "delivery": "disabled",
        "notes": "Alert readiness only; delivery is disabled by default.",
    },
}

out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

  (
    cd "${out_dir}"
    sha256sum "rules.yaml" > manifest.sha256
  )

  bash "${FABRIC_REPO_ROOT}/ops/substrate/common/signer.sh" "${out_dir}"

  echo "PASS: SLO alert rules written to ${out_path}"

done
