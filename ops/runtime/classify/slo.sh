#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ -z "${SLO_PATH:-}" || -z "${METRICS_PATH:-}" || -z "${OUT_PATH:-}" ]]; then
  echo "ERROR: SLO_PATH, METRICS_PATH, and OUT_PATH are required" >&2
  exit 2
fi

python3 - "${SLO_PATH}" "${METRICS_PATH}" "${OUT_PATH}" <<'PY'
import json
import sys
from pathlib import Path

slo_path = Path(sys.argv[1])
metrics_path = Path(sys.argv[2])
out_path = Path(sys.argv[3])

slo = json.loads(slo_path.read_text())
metrics = json.loads(metrics_path.read_text())

objectives = slo.get("spec", {}).get("objectives", {})
values = metrics.get("values", {}) if isinstance(metrics, dict) else {}

result = {
    "status": "PASS",
    "violations": [],
    "notes": [],
}

if not metrics.get("available"):
    result["notes"].append("metrics unavailable")
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    sys.exit(0)

# Availability
avail_obj = objectives.get("availability", {})
avail_target = avail_obj.get("target_percent")
avail_value = values.get("availability_percent")
if avail_target is not None and avail_value is not None:
    if avail_value < avail_target:
        result["status"] = "FAIL"
        result["violations"].append("availability")

# Latency
lat_obj = objectives.get("latency", {})
p95_target = lat_obj.get("p95_ms")
p99_target = lat_obj.get("p99_ms")
p95_value = values.get("latency_p95_ms")
p99_value = values.get("latency_p99_ms")
if p95_target is not None and p95_value is not None and p95_value > p95_target:
    result["status"] = "FAIL"
    result["violations"].append("latency_p95")
if p99_target is not None and p99_value is not None and p99_value > p99_target:
    result["status"] = "FAIL"
    result["violations"].append("latency_p99")

# Error rate
err_obj = objectives.get("error_rate", {})
err_target = err_obj.get("max_percent")
err_value = values.get("error_rate_percent")
if err_target is not None and err_value is not None and err_value > err_target:
    result["status"] = "FAIL"
    result["violations"].append("error_rate")

out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
PY
