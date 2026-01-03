#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ -z "${TENANT:-}" || -z "${ENV_ID:-}" || -z "${PROVIDER:-}" || -z "${SEVERITY:-}" || -z "${OUT_PATH:-}" ]]; then
  echo "ERROR: TENANT, ENV_ID, PROVIDER, SEVERITY, and OUT_PATH are required" >&2
  exit 2
fi

routing_path="${ALERTS_ROUTING_PATH:-${FABRIC_REPO_ROOT}/contracts/alerting/routing.yml}"

python3 - "${routing_path}" "${OUT_PATH}" <<'PY'
import json
import os
import sys
from datetime import datetime, time as dt_time, timezone
from pathlib import Path

routing_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])

tenant = os.environ.get("TENANT")
env_id = os.environ.get("ENV_ID")
provider = os.environ.get("PROVIDER")
severity = os.environ.get("SEVERITY")
alert_sink = os.environ.get("ALERT_SINK")

raw_evidence_root = os.environ.get("ALERTS_EVIDENCE_ROOT")
if raw_evidence_root:
    evidence_root = Path(raw_evidence_root)
else:
    evidence_root = Path(os.environ.get("FABRIC_REPO_ROOT", ".")) / "evidence" / "alerts"

change_start = os.environ.get("CHANGE_WINDOW_START")
change_end = os.environ.get("CHANGE_WINDOW_END")

if not routing_path.exists():
    raise SystemExit(f"missing routing config: {routing_path}")

routing = json.loads(routing_path.read_text())


def parse_duration(value):
    if not value:
        return None
    value = str(value).strip()
    digits = "".join(ch for ch in value if ch.isdigit())
    unit = value[len(digits):].strip()
    if not digits or unit not in {"s", "m", "h", "d"}:
        return None
    seconds = int(digits)
    if unit == "m":
        seconds *= 60
    elif unit == "h":
        seconds *= 3600
    elif unit == "d":
        seconds *= 86400
    return seconds


def parse_timestamp(value):
    if not value:
        return None
    text = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None


def parse_dir_stamp(name):
    if not name:
        return None
    if len(name) == 16 and name.endswith("Z"):
        try:
            return datetime.strptime(name, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
        except ValueError:
            return None
    if len(name) == 20 and name.endswith("Z"):
        try:
            return datetime.strptime(name, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except ValueError:
            return None
    return None


def now_utc():
    return datetime.now(timezone.utc)


def quiet_hours_active(env_cfg):
    quiet_cfg = routing.get("quiet_hours", {}).get(env_id, {})
    if not quiet_cfg:
        return False, None, []
    tz_name = quiet_cfg.get("timezone")
    windows = quiet_cfg.get("windows", [])
    try:
        from zoneinfo import ZoneInfo
        tz = ZoneInfo(tz_name) if tz_name else timezone.utc
    except Exception:
        tz = timezone.utc
    now_local = datetime.now(tz).time()

    def parse_time(val):
        try:
            parts = [int(p) for p in val.split(":")]
            return dt_time(parts[0], parts[1])
        except Exception:
            return None

    for window in windows:
        start = parse_time(window.get("from"))
        end = parse_time(window.get("to"))
        if not start or not end:
            continue
        if start <= end:
            if start <= now_local < end:
                return True, tz_name, windows
        else:
            if now_local >= start or now_local < end:
                return True, tz_name, windows
    return False, tz_name, windows


def rate_limit_state(env_cfg):
    rate = env_cfg.get("rate_limit") or routing.get("defaults", {}).get("rate_limit", {})
    window = rate.get("window")
    max_events = rate.get("max_events")
    window_seconds = parse_duration(window)
    if not window_seconds or not isinstance(max_events, int):
        return {
            "window": window,
            "max_events": max_events,
            "current_events": 0,
            "limited": False,
        }

    now = now_utc()
    since = now.timestamp() - window_seconds
    count = 0
    tenant_dir = evidence_root / tenant
    if tenant_dir.exists():
        for child in tenant_dir.iterdir():
            if not child.is_dir():
                continue
            stamp = parse_dir_stamp(child.name)
            if stamp and stamp.timestamp() >= since:
                count += 1

    return {
        "window": window,
        "max_events": max_events,
        "current_events": count,
        "limited": count >= max_events,
    }


def change_window_state(env_cfg):
    required = False
    defaults_required = routing.get("defaults", {}).get("maintenance_window", {}).get("required_for_prod")
    if env_id == "samakia-prod" and defaults_required:
        required = True
    require_env = env_cfg.get("require", {}).get("change_window_context")
    if require_env:
        required = True

    active = False
    start_ts = parse_timestamp(change_start)
    end_ts = parse_timestamp(change_end)
    if start_ts and end_ts:
        now = now_utc()
        active = start_ts <= now <= end_ts

    return {
        "required": required,
        "active": active,
        "start": change_start,
        "end": change_end,
    }


envs = routing.get("envs", {})
if env_id not in envs:
    raise SystemExit("env not configured in routing policy")

env_cfg = envs.get(env_id, {})

tenant_cfg = None
for item in routing.get("tenants", []):
    if item.get("id") == tenant:
        tenant_cfg = item
        break

tenant_allowed = bool(tenant_cfg and env_id in tenant_cfg.get("envs", []))
provider_enabled = routing.get("providers", {}).get(provider, {}).get("enabled", False)

emit_on = env_cfg.get("emit_on", [])
severity_mapping = env_cfg.get("severity_mapping", {})
severity_mapped = severity_mapping.get(severity)
if severity_mapped is None:
    raise SystemExit("severity mapping missing for routing policy")

emit = severity in emit_on and tenant_allowed and provider_enabled

quiet_enabled = routing.get("defaults", {}).get("quiet_hours", {}).get("enabled", False)
quiet_active, quiet_tz, quiet_windows = quiet_hours_active(env_cfg) if quiet_enabled else (False, None, [])

rate_state = rate_limit_state(env_cfg)
change_state = change_window_state(env_cfg)

suppressed_reasons = []
if not tenant_allowed:
    suppressed_reasons.append("tenant_not_allowlisted")
if not provider_enabled:
    suppressed_reasons.append("provider_disabled")
if severity not in emit_on:
    suppressed_reasons.append("severity_not_emitted")

if severity == "WARN":
    if quiet_active:
        suppressed_reasons.append("quiet_hours")
    if rate_state.get("limited"):
        suppressed_reasons.append("rate_limited")
    if change_state.get("required") and not change_state.get("active"):
        suppressed_reasons.append("change_window_inactive")

config_delivery_enabled = routing.get("defaults", {}).get("delivery", {}).get("enabled", False)
env_delivery = env_cfg.get("delivery", {}).get("enabled")
if env_delivery is not None:
    config_delivery_enabled = bool(env_delivery)

sink_cfg = routing.get("sinks", {}).get(alert_sink, {}) if alert_sink else {}
sink_enabled = sink_cfg.get("enabled", False)

payload = {
    "tenant": tenant,
    "env": env_id,
    "provider": provider,
    "severity": severity,
    "severity_mapped": severity_mapped,
    "emit_on": emit_on,
    "emit": emit,
    "suppressed": bool(suppressed_reasons),
    "suppressed_reasons": suppressed_reasons,
    "quiet_hours": {
        "enabled": quiet_enabled,
        "active": quiet_active,
        "timezone": quiet_tz,
        "windows": quiet_windows,
    },
    "rate_limit": rate_state,
    "maintenance_window": change_state,
    "delivery": {
        "config_enabled": bool(config_delivery_enabled),
        "sink": alert_sink,
        "sink_enabled": bool(sink_enabled),
    },
}

out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
