#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


TENANT="${TENANT:-}"
WORKLOAD="${WORKLOAD:-}"

if [[ -z "${TENANT}" ]]; then
  echo "ERROR: TENANT is required (use TENANT=all for all tenants)" >&2
  exit 2
fi

ALERTS_ENABLE="${ALERTS_ENABLE:-0}"
ALERT_SINK="${ALERT_SINK:-}"
ALERTS_STAMP="${ALERTS_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"

ALERTS_EVIDENCE_ROOT="${ALERTS_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/alerts}"
RUNTIME_EVIDENCE_ROOT="${RUNTIME_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/runtime-eval}"
SLO_EVIDENCE_ROOT="${SLO_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/slo}"
SLO_ALERTS_ROOT="${SLO_ALERTS_ROOT:-${FABRIC_REPO_ROOT}/artifacts/slo-alerts}"
ALERTS_ROUTING_PATH="${ALERTS_ROUTING_PATH:-${FABRIC_REPO_ROOT}/contracts/alerting/routing.yml}"

if [[ -n "${ALERT_SINK}" ]]; then
  case "${ALERT_SINK}" in
    slack|webhook|email) ;;
    *)
      echo "ERROR: ALERT_SINK must be slack, webhook, or email" >&2
      exit 2
      ;;
  esac
fi

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmpdir}" 2>/dev/null || true
}
trap cleanup EXIT

ALERTS_ENABLE="${ALERTS_ENABLE}" ALERT_SINK="${ALERT_SINK}" ALERTS_STAMP="${ALERTS_STAMP}" \
ALERTS_EVIDENCE_ROOT="${ALERTS_EVIDENCE_ROOT}" RUNTIME_EVIDENCE_ROOT="${RUNTIME_EVIDENCE_ROOT}" \
SLO_EVIDENCE_ROOT="${SLO_EVIDENCE_ROOT}" SLO_ALERTS_ROOT="${SLO_ALERTS_ROOT}" \
ALERTS_ROUTING_PATH="${ALERTS_ROUTING_PATH}" TENANT="${TENANT}" WORKLOAD="${WORKLOAD}" \
python3 - "${tmpdir}" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
import subprocess

tmp_root = Path(sys.argv[1])

repo_root = Path(os.environ["FABRIC_REPO_ROOT"])

tenant_filter = os.environ.get("TENANT")
workload_filter = os.environ.get("WORKLOAD")

stamp = os.environ.get("ALERTS_STAMP")
alerts_enable = os.environ.get("ALERTS_ENABLE", "0") == "1"
alert_sink = os.environ.get("ALERT_SINK")
ci_mode = os.environ.get("CI", "0") == "1"

alerts_evidence_root = Path(os.environ.get("ALERTS_EVIDENCE_ROOT", repo_root / "evidence" / "alerts"))
runtime_root = Path(os.environ.get("RUNTIME_EVIDENCE_ROOT", repo_root / "evidence" / "runtime-eval"))
slo_root = Path(os.environ.get("SLO_EVIDENCE_ROOT", repo_root / "evidence" / "slo"))
slo_alerts_root = Path(os.environ.get("SLO_ALERTS_ROOT", repo_root / "artifacts" / "slo-alerts"))
routing_path = Path(os.environ.get("ALERTS_ROUTING_PATH", repo_root / "contracts" / "alerting" / "routing.yml"))

format_dir = repo_root / "ops" / "alerts" / "format"
route_script = repo_root / "ops" / "alerts" / "route.sh"
redact_script = repo_root / "ops" / "alerts" / "redact.sh"

def latest_dir(base: Path):
    if not base.exists():
        return None
    dirs = sorted([p for p in base.iterdir() if p.is_dir()])
    return dirs[-1] if dirs else None


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


def collect_workloads():
    tenants = {}
    roots = [slo_root, runtime_root]
    for root in roots:
        if not root.exists():
            continue
        for tenant_dir in root.iterdir():
            if not tenant_dir.is_dir():
                continue
            tenant = tenant_dir.name
            for workload_dir in tenant_dir.iterdir():
                if not workload_dir.is_dir():
                    continue
                workloads = tenants.setdefault(tenant, set())
                workloads.add(workload_dir.name)
    if tenant_filter and tenant_filter != "all":
        return {tenant_filter: tenants.get(tenant_filter, set())}
    return tenants


def make_event_id(signal_type, workload):
    return f"{signal_type}.{workload}"


def run_route(tenant, env_id, provider, severity, out_path: Path):
    env = os.environ.copy()
    env.update({
        "TENANT": tenant,
        "ENV_ID": env_id,
        "PROVIDER": provider,
        "SEVERITY": severity,
        "OUT_PATH": str(out_path),
    })
    if alert_sink:
        env["ALERT_SINK"] = alert_sink
    env["ALERTS_ROUTING_PATH"] = str(routing_path)
    env["ALERTS_EVIDENCE_ROOT"] = str(alerts_evidence_root)
    subprocess.check_call(["bash", str(route_script)], env=env)


workloads_map = collect_workloads()
if not workloads_map or all(len(w) == 0 for w in workloads_map.values()):
    raise SystemExit("no alert inputs found (missing evidence)")
if tenant_filter and tenant_filter != "all" and tenant_filter not in workloads_map:
    raise SystemExit(f"no alert inputs found for tenant {tenant_filter}")

for tenant, workloads in workloads_map.items():
    if tenant_filter and tenant_filter != "all" and tenant != tenant_filter:
        continue
    if workload_filter:
        workloads = {workload_filter} if workload_filter in workloads else set()
    if not workloads:
        continue

    tenant_dir = tmp_root / tenant
    tenant_dir.mkdir(parents=True, exist_ok=True)

    signals_payload = {"tenant": tenant, "timestamp_utc": stamp, "signals": []}
    slo_payload = {"tenant": tenant, "timestamp_utc": stamp, "slo_states": [], "rules": []}
    routing_payload = {"tenant": tenant, "timestamp_utc": stamp, "routes": []}
    decisions_payload = {"tenant": tenant, "timestamp_utc": stamp, "decisions": []}
    delivery_payload = {"tenant": tenant, "timestamp_utc": stamp, "deliveries": []}

    for workload in sorted(workloads):
        runtime_latest = latest_dir(runtime_root / tenant / workload) if runtime_root.exists() else None
        slo_latest = latest_dir(slo_root / tenant / workload) if slo_root.exists() else None

        classification = None
        if runtime_latest:
            classification = load_json(runtime_latest / "classification.json")

        slo_state = None
        slo_input = None
        if slo_latest:
            slo_state = load_json(slo_latest / "state.json")
            slo_input = load_json(slo_latest / "inputs" / "slo.yml")

        env_id = "samakia-dev"
        provider = None
        owner = None
        if slo_input:
            meta = slo_input.get("metadata", {})
            env_id = meta.get("env") or env_id
            provider = meta.get("provider")
            owner = meta.get("owner")
        if classification and not provider:
            provider = classification.get("provider")
        provider = provider or "unknown"

        rules_path = slo_alerts_root / tenant / workload / "rules.yaml"
        rules_available = rules_path.exists()

        signals_payload["signals"].append({
            "workload": workload,
            "classification": classification,
            "source": str(runtime_latest) if runtime_latest else None,
        })

        slo_payload["slo_states"].append({
            "workload": workload,
            "state": slo_state,
            "source": str(slo_latest) if slo_latest else None,
            "env": env_id,
            "provider": provider,
            "owner": owner,
        })

        slo_payload["rules"].append({
            "workload": workload,
            "rules_path": str(rules_path),
            "available": rules_available,
        })

        events = []
        if classification:
            cls = classification.get("classification")
            if cls in {"INFRA_FAULT", "DRIFT"}:
                events.append({
                    "signal_type": "infra" if cls == "INFRA_FAULT" else "drift",
                    "severity": "FAIL",
                    "source": str(runtime_latest),
                    "summary": f"Runtime classification {cls}",
                })
            elif cls == "SLO_VIOLATION":
                if not slo_state or slo_state.get("overall_state") == "OK":
                    events.append({
                        "signal_type": "slo",
                        "severity": "FAIL",
                        "source": str(runtime_latest),
                        "summary": "Runtime classification SLO_VIOLATION",
                    })

        if slo_state:
            overall = slo_state.get("overall_state")
            if overall in {"WARN", "CRITICAL"}:
                severity = "WARN" if overall == "WARN" else "FAIL"
                summary = f"SLO state {overall}"
                events.append({
                    "signal_type": "slo",
                    "severity": severity,
                    "source": str(slo_latest),
                    "summary": summary,
                })

        if not events:
            decisions_payload["decisions"].append({
                "workload": workload,
                "signal_type": "none",
                "severity": "OK",
                "summary": "No alertable signals",
                "emit": False,
                "suppressed_reasons": ["no_alerts"],
                "delivery": {"status": "suppressed", "reasons": ["no_alerts"]},
            })
            continue

        for event in events:
            route_out = tenant_dir / f"route-{workload}-{event['signal_type']}.json"
            run_route(tenant, env_id, provider, event["severity"], route_out)
            route_payload = load_json(route_out) or {}
            routing_payload["routes"].append({
                "workload": workload,
                "signal_type": event["signal_type"],
                "route": route_payload,
            })

            emit = bool(route_payload.get("emit"))
            suppressed = bool(route_payload.get("suppressed"))
            suppressed_reasons = list(route_payload.get("suppressed_reasons", []))

            local_suppressed = []
            if event["signal_type"] == "slo" and not rules_available:
                local_suppressed.append("rules_missing")
            if local_suppressed:
                suppressed = True
                suppressed_reasons.extend(local_suppressed)

            delivery_reasons = []
            delivery_status = "suppressed"
            if not emit:
                delivery_reasons.append("emit_disabled")
            if suppressed:
                delivery_reasons.append("route_suppressed")
            if ci_mode:
                delivery_reasons.append("ci_forced_disable")
            if not alerts_enable:
                delivery_reasons.append("alerts_disabled")
            if not alert_sink:
                delivery_reasons.append("sink_missing")

            delivery_cfg = route_payload.get("delivery", {})
            if not delivery_cfg.get("config_enabled"):
                delivery_reasons.append("delivery_config_disabled")
            if alert_sink and not delivery_cfg.get("sink_enabled"):
                delivery_reasons.append("sink_disabled")

            if emit and not suppressed and alerts_enable and not ci_mode and alert_sink and delivery_cfg.get("config_enabled") and delivery_cfg.get("sink_enabled"):
                delivery_status = "ready"
            else:
                delivery_status = "suppressed"

            alert_input = {
                "tenant": tenant,
                "workload": workload,
                "env": env_id,
                "signal_type": event["signal_type"],
                "severity": event["severity"],
                "severity_mapped": route_payload.get("severity_mapped"),
                "summary": event["summary"],
                "timestamp_utc": stamp,
                "evidence_ref": f"evidence/alerts/{tenant}/{stamp}",
            }

            formatted_payload = None
            if delivery_status == "ready":
                fmt_script = format_dir / f"{alert_sink}.sh"
                alert_in = tenant_dir / f"alert-{workload}-{event['signal_type']}.json"
                alert_out = tenant_dir / f"payload-{workload}-{event['signal_type']}.json"
                alert_in.write_text(json.dumps(alert_input, indent=2, sort_keys=True) + "\n")
                fmt_env = os.environ.copy()
                fmt_env.update({"IN_PATH": str(alert_in), "OUT_PATH": str(alert_out)})
                subprocess.check_call(["bash", str(fmt_script)], env=fmt_env)
                formatted_payload = load_json(alert_out)

            decisions_payload["decisions"].append({
                "workload": workload,
                "signal_type": event["signal_type"],
                "severity": event["severity"],
                "summary": event["summary"],
                "emit": emit,
                "suppressed_reasons": suppressed_reasons,
                "delivery": {
                    "status": delivery_status,
                    "sink": alert_sink,
                    "reasons": delivery_reasons,
                },
            })

            delivery_payload["deliveries"].append({
                "workload": workload,
                "signal_type": event["signal_type"],
                "status": delivery_status,
                "sink": alert_sink,
                "reasons": delivery_reasons,
                "payload": formatted_payload,
            })

    raw_files = {
        "signals.json": signals_payload,
        "slo.json": slo_payload,
        "routing.json": routing_payload,
        "decision.json": decisions_payload,
        "delivery.json": delivery_payload,
    }

    for name, payload in raw_files.items():
        (tenant_dir / name).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

for tenant_dir in "${tmpdir}"/*; do
  if [[ ! -d "${tenant_dir}" ]]; then
    continue
  fi
  tenant="$(basename "${tenant_dir}")"
  out_dir="${ALERTS_EVIDENCE_ROOT}/${tenant}/${ALERTS_STAMP}"
  mkdir -p "${out_dir}"

  for file in signals.json slo.json routing.json decision.json delivery.json; do
    IN_PATH="${tenant_dir}/${file}" OUT_PATH="${out_dir}/${file}" bash "${FABRIC_REPO_ROOT}/ops/alerts/redact.sh"
  done

  EVIDENCE_DIR="${out_dir}" bash "${FABRIC_REPO_ROOT}/ops/alerts/evidence.sh"
  echo "PASS: alerts evidence written to ${out_dir}"

done
