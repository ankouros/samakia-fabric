#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

TENANT="${TENANT:-}"
WORKLOAD="${WORKLOAD:-}"

if [[ -z "${TENANT}" ]]; then
  echo "ERROR: TENANT is required (use TENANT=all for all SLO contracts)" >&2
  exit 2
fi

SLO_LIVE="${SLO_LIVE:-0}"
if [[ "${CI:-}" == "1" && "${SLO_LIVE}" == "1" ]]; then
  echo "ERROR: live SLO ingestion is not allowed in CI" >&2
  exit 2
fi

SLO_ROOT="${SLO_ROOT:-${FABRIC_REPO_ROOT}/contracts/tenants}"
SLO_EXAMPLES_ROOT="${SLO_EXAMPLES_ROOT:-${FABRIC_REPO_ROOT}/contracts/tenants/examples}"
OBSERVATION_PATH="${OBSERVATION_PATH:-${FABRIC_REPO_ROOT}/contracts/runtime-observation/observation.yml}"
METRICS_ROOT="${SLO_METRICS_ROOT:-${FABRIC_REPO_ROOT}/artifacts/slo-metrics}"
FIXTURES_ROOT="${FIXTURES_ROOT:-${FABRIC_REPO_ROOT}/fixtures/metrics}"

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

  out_dir="${METRICS_ROOT}/${tenant}/${workload}"
  mkdir -p "${out_dir}"
  out_path="${out_dir}/metrics.json"

  if [[ "${SLO_LIVE}" == "1" ]]; then
    if [[ -z "${PROM_URL:-}" || -z "${PROM_QUERY_FILE:-}" ]]; then
      echo "ERROR: PROM_URL and PROM_QUERY_FILE are required for live ingestion" >&2
      exit 2
    fi

    python3 - "${OBSERVATION_PATH}" "${PROM_URL}" "${PROM_QUERY_FILE}" "${out_path}" <<'PY'
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

obs_path = Path(sys.argv[1])
prom_url = sys.argv[2].rstrip("/")
queries_path = Path(sys.argv[3])
out_path = Path(sys.argv[4])

obs = json.loads(obs_path.read_text())
observed = [m.get("name") for m in obs.get("spec", {}).get("metrics", {}).get("observed", []) if isinstance(m, dict)]
observed = [m for m in observed if m]
if not observed:
    raise SystemExit("observation contract has no observed metrics")

queries = json.loads(queries_path.read_text())
if not isinstance(queries, dict):
    raise SystemExit("PROM_QUERY_FILE must be a JSON object")

end = int(time.time())
start = end - int(queries.get("window_seconds", 300))
step = int(queries.get("step_seconds", 60))

values = {}

for metric in observed:
    query = queries.get(metric)
    if not query:
        continue
    params = urllib.parse.urlencode({"query": query, "start": start, "end": end, "step": step})
    url = f"{prom_url}/api/v1/query_range?{params}"
    with urllib.request.urlopen(url) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    if payload.get("status") != "success":
        raise SystemExit(f"query failed for {metric}")
    data = payload.get("data", {})
    result = data.get("result", [])
    if not result:
        continue
    # Take the last sample from the first series
    series = result[0]
    values_list = series.get("values", [])
    if not values_list:
        continue
    values[metric] = float(values_list[-1][1])

out_payload = {
    "timestamp_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(end)),
    "values": values,
}

out_path.write_text(json.dumps(out_payload, indent=2, sort_keys=True) + "\n")
PY

  else
    fixture=""
    if [[ -f "${FIXTURES_ROOT}/${tenant}/${workload}.json" ]]; then
      fixture="${FIXTURES_ROOT}/${tenant}/${workload}.json"
    elif [[ -f "${FIXTURES_ROOT}/${workload}.json" ]]; then
      fixture="${FIXTURES_ROOT}/${workload}.json"
    elif [[ -f "${FIXTURES_ROOT}/default.json" ]]; then
      fixture="${FIXTURES_ROOT}/default.json"
    fi

    if [[ -z "${fixture}" ]]; then
      echo "ERROR: no fixture metrics found for ${tenant}/${workload}" >&2
      exit 2
    fi

    python3 - "${fixture}" "${OBSERVATION_PATH}" "${out_path}" <<'PY'
import json
import sys
from pathlib import Path

fixture = Path(sys.argv[1])
obs_path = Path(sys.argv[2])
out_path = Path(sys.argv[3])

obs = json.loads(obs_path.read_text())
observed = [m.get("name") for m in obs.get("spec", {}).get("metrics", {}).get("observed", []) if isinstance(m, dict)]
observed = [m for m in observed if m]
if not observed:
    raise SystemExit("observation contract has no observed metrics")

payload = json.loads(fixture.read_text())
values = payload.get("values", {}) if isinstance(payload, dict) else {}
if not isinstance(values, dict):
    values = {}

filtered = {k: values.get(k) for k in observed if k in values}

out_payload = {
    "timestamp_utc": payload.get("timestamp_utc"),
    "values": filtered,
}

out_path.write_text(json.dumps(out_payload, indent=2, sort_keys=True) + "\n")
PY
  fi

  echo "PASS: SLO metrics written to ${out_path}"

done
