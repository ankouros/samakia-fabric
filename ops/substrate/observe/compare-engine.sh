#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/env.sh"
# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/contract.sh"

provider_filter="${PROVIDER_FILTER:-}"

compare_tenant() {
  local tenant_dir="$1"
  local tenant_id="$2"
  local out_dir="$3"
  local stamp="$4"
  local provider="$5"

  mkdir -p "${out_dir}"
  local observed_dir
  observed_dir="${out_dir}/.observed"
  mkdir -p "${observed_dir}"

  PROVIDER_FILTER="${provider}" "${FABRIC_REPO_ROOT}/ops/substrate/observe/observe-engine.sh" \
    "${tenant_dir}" "${tenant_id}" "${observed_dir}" "${stamp}" >/dev/null

  local capacity_file
  capacity_file="${tenant_dir}/capacity.yml"

  TENANT_DIR="${tenant_dir}" TENANT_ID="${tenant_id}" PROVIDER_FILTER="${provider}" \
    OBSERVED_FILE="${observed_dir}/observed.json" CAPACITY_FILE="${capacity_file}" \
    OUT_DIR="${out_dir}" STAMP="${stamp}" python3 - <<'PY'
import json
import os
from pathlib import Path

provider_filter = os.environ.get("PROVIDER_FILTER") or None
tenant_dir = Path(os.environ["TENANT_DIR"])
tenant_id = os.environ["TENANT_ID"]
observed = json.loads(Path(os.environ["OBSERVED_FILE"]).read_text())
capacity_path = Path(os.environ["CAPACITY_FILE"])
out_dir = Path(os.environ["OUT_DIR"])
stamp = os.environ["STAMP"]

capacity = {}
limitations = []
if capacity_path.exists():
    try:
        capacity = json.loads(capacity_path.read_text())
    except json.JSONDecodeError as exc:
        limitations.append(f"capacity_read_error: {exc}")
else:
    limitations.append("capacity_missing")

contracts = []
for enabled in sorted(tenant_dir.rglob("consumers/*/enabled.yml")):
    data = json.loads(enabled.read_text())
    consumer = data.get("consumer")
    if consumer not in {"database", "message-queue", "cache", "vector"}:
        continue
    provider = data.get("executor", {}).get("provider")
    if provider_filter and provider != provider_filter:
        continue
    contracts.append(
        {
            "path": str(enabled),
            "consumer": consumer,
            "provider": provider,
            "variant": data.get("variant"),
            "endpoints": data.get("endpoints", {}),
            "resources": data.get("resources", {}),
            "slo": data.get("slo", {}),
            "failure_semantics": data.get("failure_semantics"),
        }
    )

observations = observed.get("observations", [])
obs_index = {
    f"{item.get('consumer')}:{item.get('provider')}:{item.get('variant')}": item for item in observations
}

capacity_spec = capacity.get("spec", {})

provider_limits = {
    "postgres": capacity_spec.get("database", {}).get("postgres", {}),
    "mariadb": capacity_spec.get("database", {}).get("mariadb", {}),
    "rabbitmq": capacity_spec.get("message-queue", {}).get("rabbitmq", {}),
    "dragonfly": capacity_spec.get("cache", {}).get("dragonfly", {}),
    "qdrant": capacity_spec.get("vector", {}).get("qdrant", {}),
}

if observed.get("mode") == "declared_only":
    limitations.append("declared_only: runtime inspection not enabled")

checks = []

for contract in contracts:
    key = f"{contract['consumer']}:{contract['provider']}:{contract['variant']}"
    obs = obs_index.get(key)
    status = "PASS"
    reasons = []
    attributes = obs.get("attributes") if obs else None
    reach = obs.get("reachability", {}) if obs else {}

    if not obs:
        status = "WARN"
        reasons.append("missing_observation")
    elif observed.get("mode") == "declared_only":
        status = "WARN"
        reasons.append("declared_only")

    if attributes:
        limits = provider_limits.get(contract["provider"], {})
        variant_limits = limits.get(contract["variant"], {}) if isinstance(limits, dict) else {}

    status_ref = {"value": status}

    def compare_limit(value, limit, label, hard=True):
        if value is None or limit is None:
            return
        if value > limit:
            reasons.append(f"{label}_exceeds_{'hard' if hard else 'soft'}")
            if hard:
                status_ref["value"] = "FAIL"
            elif status_ref["value"] != "FAIL":
                status_ref["value"] = "WARN"

        if contract["provider"] in {"postgres", "mariadb"}:
            compare_limit(attributes.get("databases_count"), variant_limits.get("max_databases"), "databases")
            compare_limit(attributes.get("users_count"), variant_limits.get("max_users"), "users")
            connections = variant_limits.get("max_connections", {})
            compare_limit(attributes.get("current_connections"), connections.get("soft"), "connections", hard=False)
            compare_limit(attributes.get("current_connections"), connections.get("hard"), "connections", hard=True)
        elif contract["provider"] == "rabbitmq":
            compare_limit(attributes.get("vhosts_count"), variant_limits.get("max_vhosts"), "vhosts")
            compare_limit(attributes.get("connections_count"), variant_limits.get("max_connections"), "connections")
            compare_limit(attributes.get("queues_count"), variant_limits.get("max_queues"), "queues")
        elif contract["provider"] == "dragonfly":
            compare_limit(attributes.get("connected_clients"), variant_limits.get("max_clients"), "clients")
            compare_limit(attributes.get("used_memory_mb"), variant_limits.get("max_memory_mb"), "memory")
        elif contract["provider"] == "qdrant":
            compare_limit(attributes.get("collections_count"), variant_limits.get("max_collections"), "collections")
            compare_limit(attributes.get("points_count"), variant_limits.get("max_points"), "points")

    status = status_ref["value"]

    checks.append(
        {
            "key": key,
            "consumer": contract["consumer"],
            "provider": contract["provider"],
            "variant": contract["variant"],
            "reachability": reach.get("status", "unknown"),
            "status": status,
            "reasons": reasons,
        }
    )

statuses = [item["status"] for item in checks]
if "FAIL" in statuses:
    overall = "FAIL"
elif "WARN" in statuses:
    overall = "WARN"
else:
    overall = "PASS"

drift = {
    "tenant_id": tenant_id,
    "timestamp_utc": stamp,
    "checks": checks,
}

decision = {
    "tenant_id": tenant_id,
    "timestamp_utc": stamp,
    "status": overall,
    "counts": {
        "pass": statuses.count("PASS"),
        "warn": statuses.count("WARN"),
        "fail": statuses.count("FAIL"),
    },
    "limitations": limitations,
}

declared = {
    "tenant_id": tenant_id,
    "timestamp_utc": stamp,
    "contracts": contracts,
    "capacity": capacity_spec,
}

(out_dir / "declared.json").write_text(json.dumps(declared, indent=2, sort_keys=True) + "\n")
(out_dir / "observed.json").write_text(json.dumps(observed, indent=2, sort_keys=True) + "\n")
(out_dir / "drift.json").write_text(json.dumps(drift, indent=2, sort_keys=True) + "\n")
(out_dir / "decision.json").write_text(json.dumps(decision, indent=2, sort_keys=True) + "\n")
(out_dir / "limitations.md").write_text("\n".join(limitations) + "\n")

report = [
    "# Substrate Observability Drift Report",
    "",
    f"Tenant: {tenant_id}",
    f"Timestamp (UTC): {stamp}",
    "",
    f"Status: {overall}",
    "",
    "## Checks",
]
for item in checks:
    report.append(f"- {item['key']}: {item['status']}")

(out_dir / "report.md").write_text("\n".join(report) + "\n")
PY

  "${FABRIC_REPO_ROOT}/ops/substrate/common/redaction.sh" "${out_dir}/declared.json" "${out_dir}/declared.json"
  "${FABRIC_REPO_ROOT}/ops/substrate/common/redaction.sh" "${out_dir}/observed.json" "${out_dir}/observed.json"
  "${FABRIC_REPO_ROOT}/ops/substrate/common/redaction.sh" "${out_dir}/drift.json" "${out_dir}/drift.json"
  "${FABRIC_REPO_ROOT}/ops/substrate/common/redaction.sh" "${out_dir}/decision.json" "${out_dir}/decision.json"

  rm -rf "${observed_dir}"
}

if [[ $# -lt 3 ]]; then
  echo "Usage: compare-engine.sh <tenant_dir> <tenant_id> <out_dir> [provider]" >&2
  exit 1
fi

compare_tenant "$1" "$2" "$3" "${4:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" "${provider_filter}"
