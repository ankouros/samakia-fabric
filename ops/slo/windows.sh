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
from datetime import datetime, timezone, timedelta
from pathlib import Path

slo_path = Path(sys.argv[1])
metrics_path = Path(sys.argv[2])
out_path = Path(sys.argv[3])

slo = json.loads(slo_path.read_text())
metrics = json.loads(metrics_path.read_text()) if metrics_path.exists() else {}

window = slo.get("spec", {}).get("window", {})
window_type = window.get("type")
duration = window.get("duration")
interval = window.get("evaluation_interval")

if not window_type or not duration:
    raise SystemExit("missing window configuration")
if window_type not in ("rolling", "tumbling"):
    raise SystemExit("invalid window type")

unit_seconds = {"s": 1, "m": 60, "h": 3600, "d": 86400}


def parse_duration(value):
    if not value:
        return None
    value = str(value).strip()
    num = "".join(ch for ch in value if ch.isdigit())
    unit = value[len(num):].strip()
    if not num or unit not in unit_seconds:
        return None
    return int(num) * unit_seconds[unit]


def parse_timestamp(value):
    if not value:
        return None
    text = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None


def format_timestamp(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

now = datetime.now(timezone.utc)
end_dt = parse_timestamp(metrics.get("timestamp_utc")) or now

duration_seconds = parse_duration(duration)
if duration_seconds is None:
    raise SystemExit("invalid window duration")

interval_seconds = parse_duration(interval) if interval else None

if window_type == "tumbling":
    epoch = int(end_dt.timestamp())
    end_epoch = epoch - (epoch % duration_seconds)
    end_dt = datetime.fromtimestamp(end_epoch, tz=timezone.utc)

start_dt = end_dt - timedelta(seconds=duration_seconds)

payload = {
    "type": window_type,
    "duration": duration,
    "duration_seconds": duration_seconds,
    "evaluation_interval": interval,
    "evaluation_interval_seconds": interval_seconds,
    "window_start_utc": format_timestamp(start_dt),
    "window_end_utc": format_timestamp(end_dt),
    "timestamp_source": metrics.get("timestamp_utc") or format_timestamp(now),
}

out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
