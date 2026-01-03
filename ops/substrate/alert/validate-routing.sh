#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


config_path="${FABRIC_REPO_ROOT}/contracts/alerting/routing.yml"

if [[ ! -f "${config_path}" ]]; then
  echo "[alert.validate] missing routing.yml at ${config_path}" >&2
  exit 1
fi

if [[ ! -f "${FABRIC_REPO_ROOT}/contracts/alerting/alerting.schema.json" ]]; then
  echo "[alert.validate] missing alerting.schema.json" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[alert.validate] python3 is required" >&2
  exit 1
fi

# Collect known tenant IDs from contracts/tenants (examples + top-level).
mapfile -t tenant_dirs < <(find "${FABRIC_REPO_ROOT}/contracts/tenants/examples" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null || true)
mapfile -t tenant_root_dirs < <(find "${FABRIC_REPO_ROOT}/contracts/tenants" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null || true)

valid_tenants=()
for t in "${tenant_dirs[@]}"; do
  valid_tenants+=("${t}")
done
for t in "${tenant_root_dirs[@]}"; do
  case "${t}" in
    _schema|_templates|examples) continue ;;
    *) valid_tenants+=("${t}") ;;
  esac
done

IFS=',' read -r -a tenant_csv <<<"${valid_tenants[*]}"

python3 - "${config_path}" "${tenant_csv[*]}" <<'PY'
import json
import re
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
valid_tenants = [t for t in (sys.argv[2].split() if len(sys.argv) > 2 else []) if t]

data = json.loads(config_path.read_text())

errors = []

def err(msg):
    errors.append(msg)

allowed_envs = {"samakia-dev", "samakia-shared", "samakia-prod"}
allowed_providers = {"postgres", "mariadb", "rabbitmq", "dragonfly", "qdrant"}
allowed_severity = {"info", "warning", "critical"}

if data.get("version") != "v1":
    err("version must be v1")

def get(path, default=None):
    cur = data
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur

def check_rate(rate, label):
    if not isinstance(rate, dict):
        err(f"{label} rate_limit must be object")
        return
    window = rate.get("window")
    max_events = rate.get("max_events")
    if not window or not isinstance(window, str):
        err(f"{label} rate_limit.window missing")
    if not isinstance(max_events, int) or max_events <= 0:
        err(f"{label} rate_limit.max_events must be > 0")

# Defaults
if get(["defaults", "delivery", "enabled"]) is not False:
    err("defaults.delivery.enabled must be false")
if get(["defaults", "local_evidence"]) is not True:
    err("defaults.local_evidence must be true")
check_rate(get(["defaults", "rate_limit"], {}), "defaults")
if get(["defaults", "quiet_hours", "enabled"]) is not True:
    err("defaults.quiet_hours.enabled must be true")
if get(["defaults", "maintenance_window", "required_for_prod"]) is not True:
    err("defaults.maintenance_window.required_for_prod must be true")

# Environments
envs = data.get("envs", {})
if set(envs.keys()) != allowed_envs:
    err("envs must include samakia-dev, samakia-shared, samakia-prod only")

for env, cfg in envs.items():
    if cfg.get("delivery", {}).get("enabled") is not False:
        err(f"{env} delivery.enabled must be false")
    mapping = cfg.get("severity_mapping", {})
    if mapping.get("WARN") not in allowed_severity or mapping.get("FAIL") not in allowed_severity:
        err(f"{env} severity_mapping invalid")
    emit_on = cfg.get("emit_on", [])
    if not isinstance(emit_on, list) or not emit_on:
        err(f"{env} emit_on must be list")
    for v in emit_on:
        if v not in {"WARN", "FAIL"}:
            err(f"{env} emit_on contains invalid value {v}")
    check_rate(cfg.get("rate_limit", {}), env)
    if env == "samakia-prod":
        require = cfg.get("require", {})
        if require.get("signed_evidence") is not True:
            err("samakia-prod requires signed_evidence")
        if require.get("change_window_context") is not True:
            err("samakia-prod requires change_window_context")

# Tenants
for tenant in data.get("tenants", []):
    tenant_id = tenant.get("id")
    if not tenant_id:
        err("tenant id missing")
        continue
    if "*" in tenant_id or "?" in tenant_id:
        err(f"tenant id contains wildcard: {tenant_id}")
    if valid_tenants and tenant_id not in valid_tenants:
        err(f"tenant id not found in contracts: {tenant_id}")
    envs_list = tenant.get("envs", [])
    if not isinstance(envs_list, list) or not envs_list:
        err(f"tenant {tenant_id} envs missing")
    for env in envs_list:
        if env not in allowed_envs:
            err(f"tenant {tenant_id} has invalid env {env}")

# Providers
providers = data.get("providers", {})
for name, cfg in providers.items():
    if name not in allowed_providers:
        err(f"unknown provider {name}")
    if cfg.get("enabled") is not True:
        err(f"provider {name} must be enabled true")

# Quiet hours
quiet = data.get("quiet_hours", {})
for env in allowed_envs:
    if env not in quiet:
        err(f"quiet_hours missing {env}")
        continue
    entry = quiet[env]
    if not entry.get("timezone"):
        err(f"quiet_hours {env} timezone missing")
    windows = entry.get("windows")
    if windows is None or not isinstance(windows, list):
        err(f"quiet_hours {env} windows missing")

# Sinks
sinks = data.get("sinks", {})
for sink_name in ("slack", "webhook", "email"):
    sink = sinks.get(sink_name, {})
    if sink.get("enabled") is not False:
        err(f"sink {sink_name} must be disabled")
    if not sink.get("secret_ref"):
        err(f"sink {sink_name} secret_ref missing")

# Secret scanning in values
secret_pattern = re.compile(r"(?i)(\\bpassword\\b|\\btoken\\b|\\bsecret\\b|\\bAKIA[0-9A-Z]{16}\\b|BEGIN\\s+(RSA|OPENSSH))")

def walk(obj, key=None):
    if isinstance(obj, dict):
        for k, v in obj.items():
            walk(v, k)
    elif isinstance(obj, list):
        for v in obj:
            walk(v, key)
    elif isinstance(obj, str):
        if key == "secret_ref":
            return
        if secret_pattern.search(obj):
            err("routing.yml contains secret-like value")

walk(data)

if errors:
    sys.stderr.write("[alert.validate] FAIL\n")
    for e in errors:
        sys.stderr.write(f"- {e}\n")
    sys.exit(1)

print("[alert.validate] PASS")
PY
