#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/env.sh"
# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/connectivity.sh"

provider_filter="${PROVIDER_FILTER:-}"

collect_endpoints() {
  local tenant_dir="$1"
  local provider="$2"
  local out_file="$3"

  TENANT_DIR="${tenant_dir}" PROVIDER_FILTER="${provider}" python3 - <<'PY' >"${out_file}"
import json
import os
from pathlib import Path

tenant_dir = Path(os.environ["TENANT_DIR"])
provider_filter = os.environ.get("PROVIDER_FILTER") or None

entries = []
for enabled in sorted(tenant_dir.rglob("consumers/*/enabled.yml")):
    data = json.loads(enabled.read_text())
    consumer = data.get("consumer")
    if consumer not in {"database", "message-queue", "cache", "vector"}:
        continue
    provider = data.get("executor", {}).get("provider")
    if provider_filter and provider != provider_filter:
        continue
    variant = data.get("variant")
    endpoints = data.get("endpoints", {})
    entries.append(
        {
            "key": f"{consumer}:{provider}:{variant}",
            "consumer": consumer,
            "provider": provider,
            "variant": variant,
            "host": endpoints.get("host"),
            "port": endpoints.get("port"),
            "protocol": endpoints.get("protocol"),
            "tls_required": endpoints.get("tls_required"),
        }
    )

print(json.dumps(entries, indent=2, sort_keys=True))
PY
}

build_observed() {
  local tenant_dir="$1"
  local tenant_id="$2"
  local provider="$3"
  local stamp="$4"
  local reachability_file="$5"
  local out_file="$6"

  TENANT_DIR="${tenant_dir}" PROVIDER_FILTER="${provider}" TENANT_ID="${tenant_id}" \
    STAMP="${stamp}" REACHABILITY_FILE="${reachability_file}" python3 - <<'PY' >"${out_file}"
import json
import os
from pathlib import Path

provider_filter = os.environ.get("PROVIDER_FILTER") or None
tenant_dir = Path(os.environ["TENANT_DIR"])
tenant_id = os.environ["TENANT_ID"]
stamp = os.environ["STAMP"]
reachability = json.loads(Path(os.environ["REACHABILITY_FILE"]).read_text())

attribute_map = {
    "postgres": [
        "current_connections",
        "max_connections",
        "databases_count",
        "users_count",
        "replication_status",
        "disk_usage_gb",
    ],
    "mariadb": [
        "current_connections",
        "max_connections",
        "databases_count",
        "users_count",
        "replication_status",
        "disk_usage_gb",
    ],
    "rabbitmq": [
        "nodes_up",
        "vhosts_count",
        "connections_count",
        "queues_count",
        "quorum_policy",
        "memory_watermark",
    ],
    "dragonfly": [
        "used_memory_mb",
        "max_memory_mb",
        "connected_clients",
        "eviction_policy",
        "replication_health",
        "key_prefix_enforced",
    ],
    "qdrant": [
        "collections_count",
        "points_count",
        "replication_factor",
        "shard_health",
        "storage_usage_gb",
    ],
}

observations = []
providers = set()

for enabled in sorted(tenant_dir.rglob("consumers/*/enabled.yml")):
    data = json.loads(enabled.read_text())
    consumer = data.get("consumer")
    if consumer not in {"database", "message-queue", "cache", "vector"}:
        continue
    provider = data.get("executor", {}).get("provider")
    if provider_filter and provider != provider_filter:
        continue
    variant = data.get("variant")
    endpoints = data.get("endpoints", {})
    key = f"{consumer}:{provider}:{variant}"
    providers.add(provider)
    reach = reachability.get(key, {"status": "unknown", "detail": "not_checked"})
    attributes = {field: None for field in attribute_map.get(provider, [])}
    observations.append(
        {
            "consumer": consumer,
            "provider": provider,
            "variant": variant,
            "endpoints": endpoints,
            "reachability": reach,
            "attributes": attributes,
        }
    )

observed = {
    "tenant_id": tenant_id,
    "timestamp_utc": stamp,
    "mode": "declared_only",
    "providers": sorted(providers),
    "observations": observations,
}

print(json.dumps(observed, indent=2, sort_keys=True))
PY
}

observe_tenant() {
  local tenant_dir="$1"
  local tenant_id="$2"
  local out_dir="$3"
  local stamp="$4"
  local provider="$5"

  mkdir -p "${out_dir}"
  local endpoints_json
  endpoints_json="${out_dir}/.endpoints.json"
  local reachability_json
  reachability_json="${out_dir}/.reachability.json"

  collect_endpoints "${tenant_dir}" "${provider}" "${endpoints_json}"
  connectivity_check "${endpoints_json}" "${reachability_json}" "${stamp}"
  build_observed "${tenant_dir}" "${tenant_id}" "${provider}" "${stamp}" "${reachability_json}" "${out_dir}/observed.json"

  {
    echo "# Substrate Observability (Read-Only)"
    echo ""
    echo "Tenant: ${tenant_id}"
    echo "Timestamp (UTC): ${stamp}"
    if [[ -n "${provider}" ]]; then
      echo "Provider filter: ${provider}"
    fi
    echo ""
    echo "Mode: declared_only"
    echo "Limitations: runtime inspection not enabled; reachability only"
  } >"${out_dir}/report.md"

  echo "declared_only: runtime inspection not enabled" >"${out_dir}/limitations.md"
  rm -f "${endpoints_json}" "${reachability_json}"
}

if [[ $# -lt 3 ]]; then
  echo "Usage: observe-engine.sh <tenant_dir> <tenant_id> <out_dir> [provider]" >&2
  exit 1
fi

observe_tenant "$1" "$2" "$3" "${4:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" "${provider_filter}"
