#!/usr/bin/env bash
set -euo pipefail

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
metrics = json.loads(metrics_path.read_text()) if metrics_path.exists() else {}

objectives = slo.get("spec", {}).get("objectives", {})
error_budget = slo.get("spec", {}).get("error_budget", {})

budget_percent = error_budget.get("percent", 0.0)
try:
    budget_percent = float(budget_percent)
except (TypeError, ValueError):
    budget_percent = 0.0
policy = error_budget.get("policy", "")

values = metrics.get("values", {}) if isinstance(metrics, dict) else {}
missing_metrics = metrics.get("missing_metrics", []) if isinstance(metrics, dict) else []


def build_record(name, target, value, unit, budget_abs, budget_mode):
    record = {
        "objective": name,
        "target": target,
        "value": value,
        "unit": unit,
        "budget_percent": budget_percent,
        "budget_absolute": budget_abs,
        "budget_mode": budget_mode,
        "breach": None,
        "burn_rate": None,
        "remaining": None,
        "objective_met": None,
        "notes": [],
    }
    if target is None:
        record["notes"].append("missing target")
        return record
    if value is None:
        record["notes"].append("missing metric")
        record["objective_met"] = False
        return record

    breach = 0.0
    if name == "availability":
        breach = max(0.0, float(target) - float(value))
    else:
        breach = max(0.0, float(value) - float(target))

    record["breach"] = breach
    record["objective_met"] = breach == 0.0

    if budget_abs is not None and budget_abs > 0:
        record["burn_rate"] = breach / budget_abs
        record["remaining"] = max(0.0, budget_abs - breach)
    else:
        record["notes"].append("error budget is zero")

    return record


budgets = {}

avail_target = objectives.get("availability", {}).get("target_percent")
avail_value = values.get("availability_percent")
budgets["availability"] = build_record(
    "availability",
    avail_target,
    avail_value,
    "percent",
    float(budget_percent),
    "percent-points",
)

latency = objectives.get("latency", {})
p95_target = latency.get("p95_ms")
p99_target = latency.get("p99_ms")
p95_value = values.get("latency_p95_ms")
p99_value = values.get("latency_p99_ms")

p95_budget = (float(p95_target) * float(budget_percent) / 100.0) if p95_target is not None else None
p99_budget = (float(p99_target) * float(budget_percent) / 100.0) if p99_target is not None else None

budgets["latency_p95"] = build_record(
    "latency_p95",
    p95_target,
    p95_value,
    "ms",
    p95_budget,
    "relative",
)

budgets["latency_p99"] = build_record(
    "latency_p99",
    p99_target,
    p99_value,
    "ms",
    p99_budget,
    "relative",
)

err_target = objectives.get("error_rate", {}).get("max_percent")
err_value = values.get("error_rate_percent")
budgets["error_rate"] = build_record(
    "error_rate",
    err_target,
    err_value,
    "percent",
    float(budget_percent),
    "percent-points",
)

burn_rates = [r.get("burn_rate") for r in budgets.values() if isinstance(r.get("burn_rate"), (int, float))]
remaining = [r.get("remaining") for r in budgets.values() if isinstance(r.get("remaining"), (int, float))]

payload = {
    "tenant": slo.get("spec", {}).get("scope", {}).get("tenant") or slo.get("metadata", {}).get("tenant"),
    "workload": slo.get("spec", {}).get("scope", {}).get("workload") or slo.get("metadata", {}).get("workload"),
    "timestamp_utc": metrics.get("timestamp_utc"),
    "policy": policy,
    "budget_percent": budget_percent,
    "missing_metrics": missing_metrics,
    "objectives": budgets,
    "overall": {
        "burn_rate": max(burn_rates) if burn_rates else None,
        "remaining": min(remaining) if remaining else None,
    },
}

out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
