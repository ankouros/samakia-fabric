#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

if [[ -z "${OUT_PATH:-}" ]]; then
  echo "ERROR: OUT_PATH is required" >&2
  exit 2
fi

obs_path="${OBSERVATION_PATH:-${FABRIC_REPO_ROOT}/contracts/runtime-observation/observation.yml}"
metrics_source="${METRICS_SOURCE:-}"

python3 - "${obs_path}" "${metrics_source}" "${OUT_PATH}" <<'PY'
import json
import sys
from pathlib import Path

obs_path = Path(sys.argv[1])
metrics_source = sys.argv[2]
out_path = Path(sys.argv[3])

obs = json.loads(obs_path.read_text())
observed = [m.get("name") for m in obs.get("spec", {}).get("metrics", {}).get("observed", []) if isinstance(m, dict)]
observed = [m for m in observed if m]

payload = {
    "available": False,
    "timestamp_utc": None,
    "values": {},
    "observed_metrics": observed,
    "missing_metrics": observed,
    "source": None,
}

if metrics_source:
    src_path = Path(metrics_source)
    if src_path.exists():
        data = json.loads(src_path.read_text())
        values = data.get("values", {}) if isinstance(data, dict) else {}
        if isinstance(values, dict):
            filtered = {k: values.get(k) for k in observed if k in values}
            payload["values"] = filtered
            payload["missing_metrics"] = [m for m in observed if m not in filtered]
            payload["timestamp_utc"] = data.get("timestamp_utc")
            payload["source"] = src_path.name
            payload["available"] = bool(filtered)

out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
