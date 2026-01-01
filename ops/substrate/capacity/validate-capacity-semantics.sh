#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

contracts_root="${FABRIC_REPO_ROOT}/contracts/tenants"

mapfile -t capacity_files < <(find "${contracts_root}" -type f -name "capacity.yml" -print | sort)

if [[ ${#capacity_files[@]} -eq 0 ]]; then
  echo "ERROR: no capacity.yml files found under ${contracts_root}" >&2
  exit 1
fi

CAPACITY_LIST="$(printf '%s\n' "${capacity_files[@]}")" ROOT_DIR="${contracts_root}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

capacity_files = [Path(p) for p in os.environ["CAPACITY_LIST"].splitlines() if p]
root_dir = Path(os.environ["ROOT_DIR"])

errors = []

thresholds = {
    "max_databases": 100000,
    "max_users": 100000,
    "max_connections": 100000,
    "max_queues": 100000,
    "max_vhosts": 100000,
    "max_message_bytes": 1073741824,
    "max_storage_gb": 10000,
    "max_cpu": 256,
    "max_memory_gb": 4096,
    "max_memory_mb": 1048576,
    "max_clients": 1000000,
    "max_points": 1000000000,
    "max_collections": 10000,
    "replication_factor": 10,
}


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        errors.append(f"{path}: invalid JSON ({exc})")
        return None


def ensure_single_cluster(single, cluster, label, fields):
    for field in fields:
        single_val = single.get(field)
        cluster_val = cluster.get(field)
        if isinstance(single_val, dict) and isinstance(cluster_val, dict):
            for subkey in ("soft", "hard"):
                sval = single_val.get(subkey)
                cval = cluster_val.get(subkey)
                if isinstance(sval, (int, float)) and isinstance(cval, (int, float)):
                    if sval > cval:
                        errors.append(f"{label}: single {field}.{subkey} ({sval}) exceeds cluster ({cval})")
        elif isinstance(single_val, (int, float)) and isinstance(cluster_val, (int, float)):
            if single_val > cluster_val:
                errors.append(f"{label}: single {field} ({single_val}) exceeds cluster ({cluster_val})")


def exceeds_threshold(field, value):
    limit = thresholds.get(field)
    if limit is None:
        return False
    return isinstance(value, (int, float)) and value > limit


for capacity in capacity_files:
    data = load_json(capacity)
    if not data:
        continue

    tenant_id = data.get("metadata", {}).get("tenant_id")
    spec = data.get("spec", {})
    spec_tenant = spec.get("tenant")
    tenant_dir = capacity.parent
    folder_name = tenant_dir.name
    is_template = folder_name == "_templates"
    if not is_template and (tenant_id != spec_tenant or tenant_id != folder_name):
        errors.append(f"{capacity}: tenant mismatch (metadata/spec/folder)")

    budget_class = spec.get("budget_class")
    defaults = spec.get("defaults", {})
    mode = defaults.get("mode")
    enforce = defaults.get("enforce")
    if budget_class == "prod" and mode != "deny_on_exceed":
        errors.append(f"{capacity}: prod budget_class must use defaults.mode=deny_on_exceed")
    if enforce is not True:
        errors.append(f"{capacity}: defaults.enforce should be true")

    overrides = spec.get("overrides", [])
    override_refs = set()
    if isinstance(overrides, list):
        for entry in overrides:
            if not isinstance(entry, dict):
                errors.append(f"{capacity}: overrides entries must be objects")
                continue
            ref = entry.get("consumer_ref")
            reason = entry.get("reason")
            if not ref or not isinstance(ref, str):
                errors.append(f"{capacity}: override consumer_ref is required")
                continue
            if not reason or not isinstance(reason, str):
                errors.append(f"{capacity}: override reason is required")
            override_refs.add(ref)
            if not (root_dir / ref).exists():
                errors.append(f"{capacity}: override consumer_ref not found: {ref}")
    else:
        errors.append(f"{capacity}: overrides must be a list")

    def has_override(consumer):
        needle = f"/consumers/{consumer}/"
        return any(needle in ref for ref in override_refs)

    database = spec.get("database", {})
    postgres = database.get("postgres", {})
    mariadb = database.get("mariadb", {})
    for provider_name, provider in (("postgres", postgres), ("mariadb", mariadb)):
        single = provider.get("single", {})
        cluster = provider.get("cluster", {})
        ensure_single_cluster(single, cluster, f"{capacity}:{provider_name}", [
            "max_databases", "max_users", "max_storage_gb", "max_cpu", "max_memory_gb"
        ])
        ensure_single_cluster(single, cluster, f"{capacity}:{provider_name}", ["max_connections"])
        for variant in ("single", "cluster"):
            limits = provider.get(variant, {})
            for field in ("max_databases", "max_users", "max_storage_gb", "max_cpu", "max_memory_gb"):
                if exceeds_threshold(field, limits.get(field)) and not has_override("database"):
                    errors.append(f"{capacity}:{provider_name}:{variant} {field} exceeds sanity threshold without override")
            connections = limits.get("max_connections", {})
            for subkey in ("soft", "hard"):
                if exceeds_threshold("max_connections", connections.get(subkey)) and not has_override("database"):
                    errors.append(f"{capacity}:{provider_name}:{variant} max_connections.{subkey} exceeds threshold without override")
            soft = connections.get("soft")
            hard = connections.get("hard")
            if isinstance(soft, (int, float)) and isinstance(hard, (int, float)) and soft > hard:
                errors.append(f"{capacity}:{provider_name}:{variant} max_connections.soft exceeds hard")

    rabbitmq = spec.get("message-queue", {}).get("rabbitmq", {})
    ensure_single_cluster(rabbitmq.get("single", {}), rabbitmq.get("cluster", {}), f"{capacity}:rabbitmq", [
        "max_vhosts", "max_users", "max_connections", "max_queues", "max_message_bytes"
    ])
    for variant in ("single", "cluster"):
        limits = rabbitmq.get(variant, {})
        for field in ("max_vhosts", "max_users", "max_connections", "max_queues", "max_message_bytes"):
            if exceeds_threshold(field, limits.get(field)) and not has_override("message-queue"):
                errors.append(f"{capacity}:rabbitmq:{variant} {field} exceeds threshold without override")

    dragonfly = spec.get("cache", {}).get("dragonfly", {})
    ensure_single_cluster(dragonfly.get("single", {}), dragonfly.get("cluster", {}), f"{capacity}:dragonfly", [
        "max_memory_mb", "max_clients"
    ])
    for variant in ("single", "cluster"):
        limits = dragonfly.get(variant, {})
        if limits.get("require_prefix") is not True:
            errors.append(f"{capacity}:dragonfly:{variant} require_prefix must be true")
        if not isinstance(limits.get("tenant_key_prefix"), str) or not limits.get("tenant_key_prefix"):
            errors.append(f"{capacity}:dragonfly:{variant} tenant_key_prefix must be set")
        for field in ("max_memory_mb", "max_clients"):
            if exceeds_threshold(field, limits.get(field)) and not has_override("cache"):
                errors.append(f"{capacity}:dragonfly:{variant} {field} exceeds threshold without override")

    qdrant = spec.get("vector", {}).get("qdrant", {})
    ensure_single_cluster(qdrant.get("single", {}), qdrant.get("cluster", {}), f"{capacity}:qdrant", [
        "max_collections", "max_points", "max_storage_gb", "replication_factor"
    ])
    for variant in ("single", "cluster"):
        limits = qdrant.get(variant, {})
        for field in ("max_collections", "max_points", "max_storage_gb", "replication_factor"):
            if exceeds_threshold(field, limits.get(field)) and not has_override("vector"):
                errors.append(f"{capacity}:qdrant:{variant} {field} exceeds threshold without override")

if errors:
    for err in errors:
        print(f"FAIL capacity semantics: {err}")
    sys.exit(1)

for capacity in capacity_files:
    print(f"PASS capacity semantics: {capacity}")

sys.exit(0)
PY
