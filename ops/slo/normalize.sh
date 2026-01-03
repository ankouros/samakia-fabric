#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ -z "${IN_PATH:-}" || -z "${OUT_PATH:-}" ]]; then
  echo "ERROR: IN_PATH and OUT_PATH are required" >&2
  exit 2
fi

obs_path="${OBSERVATION_PATH:-${FABRIC_REPO_ROOT}/contracts/runtime-observation/observation.yml}"

python3 - "${obs_path}" "${IN_PATH}" "${OUT_PATH}" <<'PY'
import json
import sys
from pathlib import Path

obs_path = Path(sys.argv[1])
metrics_path = Path(sys.argv[2])
out_path = Path(sys.argv[3])

try:
    obs = json.loads(obs_path.read_text())
except Exception as exc:
    raise SystemExit(f"failed to load observation contract: {exc}")

observed = [m.get("name") for m in obs.get("spec", {}).get("metrics", {}).get("observed", []) if isinstance(m, dict)]
observed = [m for m in observed if m]
if not observed:
    raise SystemExit("observation contract has no observed metrics")

payload = {
    "available": False,
    "timestamp_utc": None,
    "values": {},
    "observed_metrics": observed,
    "missing_metrics": observed,
    "source": None,
}

if metrics_path.exists():
    data = json.loads(metrics_path.read_text())
    values = data.get("values", {}) if isinstance(data, dict) else {}
    filtered = {}
    if isinstance(values, dict):
        if observed:
            for metric in observed:
                val = values.get(metric)
                if val is None:
                    continue
                filtered[metric] = val
        else:
            filtered = {k: v for k, v in values.items() if v is not None}
    payload["values"] = filtered
    payload["missing_metrics"] = [m for m in observed if m not in filtered]
    payload["timestamp_utc"] = data.get("timestamp_utc")
    payload["source"] = metrics_path.name
    payload["available"] = bool(filtered)

out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
