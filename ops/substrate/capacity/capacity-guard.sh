#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/env.sh"

TENANT="${TENANT:-all}"
CAPACITY_EVIDENCE_ROOT="${CAPACITY_EVIDENCE_ROOT:-}"
CAPACITY_STAMP="${CAPACITY_STAMP:-}"  # optional; if empty, generated per run

"${FABRIC_REPO_ROOT}/ops/substrate/capacity/validate-capacity-schema.sh"
"${FABRIC_REPO_ROOT}/ops/substrate/capacity/validate-capacity-semantics.sh"

TENANTS_ROOT="${TENANTS_ROOT}" CAPACITY_EVIDENCE_ROOT="${CAPACITY_EVIDENCE_ROOT}" CAPACITY_STAMP="${CAPACITY_STAMP}" TENANT_TARGET="${TENANT}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path
from datetime import datetime, timezone

root = Path(os.environ["TENANTS_ROOT"])
capacity_root = os.environ.get("CAPACITY_EVIDENCE_ROOT") or None
stamp = os.environ.get("CAPACITY_STAMP") or None
if not stamp:
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

tenant_target = os.environ.get("TENANT_TARGET") or "all"

errors = []


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        errors.append(f"{path}: invalid JSON ({exc})")
        return None


def count_entry(value):
    if isinstance(value, list):
        return len([item for item in value if item])
    if isinstance(value, str) and value.strip():
        return 1
    return 0


def ensure_number(value, path, default=0):
    if isinstance(value, (int, float)):
        return value
    if value is None:
        return default
    raise ValueError(f"{path}: expected number")


if tenant_target == "all":
    tenant_dirs = [p for p in sorted(root.iterdir()) if p.is_dir()]
else:
    tenant_dirs = [root / tenant_target]

results = []

for tenant_dir in tenant_dirs:
    tenant_id = tenant_dir.name
    capacity_path = tenant_dir / "capacity.yml"
    if not capacity_path.exists():
        results.append({"tenant": tenant_id, "status": "FAIL", "violations": [f"missing {capacity_path}"]})
        continue

    capacity = load_json(capacity_path)
    if not capacity:
        results.append({"tenant": tenant_id, "status": "FAIL", "violations": ["capacity.yml invalid"]})
        continue

    spec = capacity.get("spec", {})
    budget_class = spec.get("budget_class")
    defaults = spec.get("defaults", {})
    mode = defaults.get("mode", "deny_on_exceed")
    enforce = defaults.get("enforce", True)
    totals = {
        "database": {"max_databases": 0, "max_users": 0, "max_connections": {"soft": 0, "hard": 0}, "max_storage_gb": 0, "max_cpu": 0, "max_memory_gb": 0},
        "message-queue": {"max_vhosts": 0, "max_users": 0, "max_connections": 0, "max_queues": 0, "max_message_bytes": 0, "policy_defaults": {}},
        "cache": {"max_memory_mb": 0, "max_clients": 0, "require_prefix": True, "tenant_key_prefix": None, "eviction_policy": None},
        "vector": {"max_collections": 0, "max_points": 0, "max_storage_gb": 0, "replication_factor": 0},
    }

    overrides = spec.get("overrides", []) if isinstance(spec.get("overrides", []), list) else []
    override_consumers = set()
    override_refs = set()
    consumer_keys = list(totals.keys())
    for entry in overrides:
        if not isinstance(entry, dict):
            continue
        ref = entry.get("consumer_ref") or ""
        if isinstance(ref, str):
            override_refs.add(ref)
            for consumer_key in consumer_keys:
                if f"/consumers/{consumer_key}/" in ref:
                    override_consumers.add(consumer_key)

    provider_variants = {"database": set(), "message-queue": set(), "cache": set(), "vector": set()}
    provider_usage = {"database": set(), "message-queue": set(), "cache": set(), "vector": set()}

    enabled_files = sorted(tenant_dir.rglob("consumers/**/enabled.yml"))
    for enabled in enabled_files:
        data = load_json(enabled)
        if not data:
            continue
        consumer = data.get("consumer")
        if consumer not in totals:
            continue
        provider = data.get("executor", {}).get("provider")
        if isinstance(provider, str):
            provider_usage[consumer].add(provider)
        variant = data.get("variant")
        if variant in {"single", "cluster"}:
            provider_variants[consumer].add(variant)
        resources = data.get("resources", {})

        if consumer == "database":
            totals[consumer]["max_databases"] += count_entry(resources.get("database")) + count_entry(resources.get("databases"))
            totals[consumer]["max_users"] += count_entry(resources.get("user")) + count_entry(resources.get("users"))
            conn = resources.get("max_connections", {})
            totals[consumer]["max_connections"]["soft"] += ensure_number(conn.get("soft"), f"{enabled}: max_connections.soft", 0)
            totals[consumer]["max_connections"]["hard"] += ensure_number(conn.get("hard"), f"{enabled}: max_connections.hard", 0)
            totals[consumer]["max_storage_gb"] += ensure_number(resources.get("max_storage_gb"), f"{enabled}: max_storage_gb", 0)
            totals[consumer]["max_cpu"] += ensure_number(resources.get("max_cpu"), f"{enabled}: max_cpu", 0)
            totals[consumer]["max_memory_gb"] += ensure_number(resources.get("max_memory_gb"), f"{enabled}: max_memory_gb", 0)

        if consumer == "message-queue":
            totals[consumer]["max_vhosts"] += count_entry(resources.get("vhost")) + count_entry(resources.get("vhosts"))
            totals[consumer]["max_users"] += count_entry(resources.get("user")) + count_entry(resources.get("users"))
            totals[consumer]["max_connections"] += ensure_number(resources.get("max_connections"), f"{enabled}: max_connections", 0)
            totals[consumer]["max_queues"] += ensure_number(resources.get("max_queues"), f"{enabled}: max_queues", 0)
            totals[consumer]["max_message_bytes"] = max(
                totals[consumer]["max_message_bytes"],
                ensure_number(resources.get("max_message_bytes"), f"{enabled}: max_message_bytes", 0),
            )
            if isinstance(resources.get("policy_defaults"), dict):
                totals[consumer]["policy_defaults"] = resources.get("policy_defaults")

        if consumer == "cache":
            totals[consumer]["max_memory_mb"] += ensure_number(resources.get("max_memory_mb"), f"{enabled}: max_memory_mb", 0)
            totals[consumer]["max_clients"] += ensure_number(resources.get("max_clients"), f"{enabled}: max_clients", 0)
            if "require_prefix" in resources:
                totals[consumer]["require_prefix"] = bool(resources.get("require_prefix"))
            if resources.get("tenant_key_prefix"):
                totals[consumer]["tenant_key_prefix"] = resources.get("tenant_key_prefix")
            if resources.get("eviction_policy"):
                totals[consumer]["eviction_policy"] = resources.get("eviction_policy")

        if consumer == "vector":
            collections = resources.get("collections")
            if isinstance(collections, list):
                totals[consumer]["max_collections"] += len(collections)
            else:
                totals[consumer]["max_collections"] += ensure_number(resources.get("max_collections"), f"{enabled}: max_collections", 0)
            totals[consumer]["max_points"] += ensure_number(resources.get("max_points"), f"{enabled}: max_points", 0)
            totals[consumer]["max_storage_gb"] += ensure_number(resources.get("max_storage_gb"), f"{enabled}: max_storage_gb", 0)
            totals[consumer]["replication_factor"] = max(
                totals[consumer]["replication_factor"],
                ensure_number(resources.get("replication_factor"), f"{enabled}: replication_factor", 0),
            )

    violations = []
    override_notes = []
    limits_summary = {}

    def pick_variant(consumer):
        return "cluster" if "cluster" in provider_variants.get(consumer, set()) else "single"

    def add_violation(consumer, message):
        if consumer in override_consumers:
            override_notes.append(f"{consumer}: {message}")
        else:
            violations.append(message)

    # Database limits
    for provider in ("postgres", "mariadb"):
        if provider_usage["database"] and provider not in provider_usage["database"]:
            continue
        limits = spec.get("database", {}).get(provider, {})
        variant = pick_variant("database")
        limit_set = limits.get(variant, {})
        limits_summary[f"database:{provider}:{variant}"] = limit_set
        totals_db = totals["database"]
        if totals_db["max_databases"] > limit_set.get("max_databases", 0):
            add_violation("database", f"{provider} databases {totals_db['max_databases']} exceeds {limit_set.get('max_databases')}")
        if totals_db["max_users"] > limit_set.get("max_users", 0):
            add_violation("database", f"{provider} users {totals_db['max_users']} exceeds {limit_set.get('max_users')}")
        if totals_db["max_connections"]["soft"] > limit_set.get("max_connections", {}).get("soft", 0):
            add_violation("database", "connections soft exceed limit")
        if totals_db["max_connections"]["hard"] > limit_set.get("max_connections", {}).get("hard", 0):
            add_violation("database", "connections hard exceed limit")
        if totals_db["max_storage_gb"] > limit_set.get("max_storage_gb", 0):
            add_violation("database", "storage exceeds limit")
        if totals_db["max_cpu"] > limit_set.get("max_cpu", 0):
            add_violation("database", "cpu exceeds limit")
        if totals_db["max_memory_gb"] > limit_set.get("max_memory_gb", 0):
            add_violation("database", "memory exceeds limit")

    # RabbitMQ
    variant = pick_variant("message-queue")
    if provider_usage["message-queue"] and "rabbitmq" not in provider_usage["message-queue"]:
        rabbit_limits = {}
    else:
        rabbit_limits = spec.get("message-queue", {}).get("rabbitmq", {}).get(variant, {})
    limits_summary[f"message-queue:rabbitmq:{variant}"] = rabbit_limits
    totals_mq = totals["message-queue"]
    if totals_mq["max_vhosts"] > rabbit_limits.get("max_vhosts", 0):
        add_violation("message-queue", "rabbitmq vhosts exceed limit")
    if totals_mq["max_users"] > rabbit_limits.get("max_users", 0):
        add_violation("message-queue", "rabbitmq users exceed limit")
    if totals_mq["max_connections"] > rabbit_limits.get("max_connections", 0):
        add_violation("message-queue", "rabbitmq connections exceed limit")
    if totals_mq["max_queues"] > rabbit_limits.get("max_queues", 0):
        add_violation("message-queue", "rabbitmq queues exceed limit")
    if totals_mq["max_message_bytes"] > rabbit_limits.get("max_message_bytes", 0):
        add_violation("message-queue", "rabbitmq max_message_bytes exceeds limit")
    policy_defaults = rabbit_limits.get("policy_defaults", {})
    if policy_defaults and totals_mq.get("policy_defaults"):
        if totals_mq["policy_defaults"].get("queue_type") != policy_defaults.get("queue_type"):
            add_violation("message-queue", "rabbitmq queue_type does not match policy defaults")
        if totals_mq["policy_defaults"].get("ha_mode") != policy_defaults.get("ha_mode"):
            add_violation("message-queue", "rabbitmq ha_mode does not match policy defaults")

    # Dragonfly
    variant = pick_variant("cache")
    if provider_usage["cache"] and "dragonfly" not in provider_usage["cache"]:
        cache_limits = {}
    else:
        cache_limits = spec.get("cache", {}).get("dragonfly", {}).get(variant, {})
    limits_summary[f"cache:dragonfly:{variant}"] = cache_limits
    totals_cache = totals["cache"]
    if totals_cache["max_memory_mb"] > cache_limits.get("max_memory_mb", 0):
        add_violation("cache", "dragonfly max_memory_mb exceeds limit")
    if totals_cache["max_clients"] > cache_limits.get("max_clients", 0):
        add_violation("cache", "dragonfly max_clients exceeds limit")
    if cache_limits.get("require_prefix") and not totals_cache.get("require_prefix"):
        add_violation("cache", "dragonfly require_prefix must be true")
    if cache_limits.get("tenant_key_prefix") and totals_cache.get("tenant_key_prefix"):
        if not str(totals_cache["tenant_key_prefix"]).startswith(str(cache_limits.get("tenant_key_prefix"))):
            add_violation("cache", "dragonfly tenant_key_prefix does not match capacity")

    # Qdrant
    variant = pick_variant("vector")
    if provider_usage["vector"] and "qdrant" not in provider_usage["vector"]:
        qdrant_limits = {}
    else:
        qdrant_limits = spec.get("vector", {}).get("qdrant", {}).get(variant, {})
    limits_summary[f"vector:qdrant:{variant}"] = qdrant_limits
    totals_vector = totals["vector"]
    if totals_vector["max_collections"] > qdrant_limits.get("max_collections", 0):
        add_violation("vector", "qdrant max_collections exceeds limit")
    if totals_vector["max_points"] > qdrant_limits.get("max_points", 0):
        add_violation("vector", "qdrant max_points exceeds limit")
    if totals_vector["max_storage_gb"] > qdrant_limits.get("max_storage_gb", 0):
        add_violation("vector", "qdrant max_storage_gb exceeds limit")
    if totals_vector["replication_factor"] > qdrant_limits.get("replication_factor", 0):
        add_violation("vector", "qdrant replication_factor exceeds limit")

    status = "PASS"
    if violations:
        if mode == "deny_on_exceed":
            status = "FAIL"
        else:
            status = "WARN"

    if enforce is not True and status == "FAIL":
        status = "WARN"

    result = {
        "tenant": tenant_id,
        "budget_class": budget_class,
        "mode": mode,
        "status": status,
        "violations": violations,
        "overrides": sorted(override_refs),
        "override_notes": override_notes,
        "totals": totals,
        "limits": limits_summary,
    }
    results.append(result)

    if capacity_root:
        out_dir = Path(capacity_root) / tenant_id / stamp / "substrate-capacity"
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "computed-consumption.json").write_text(json.dumps(totals, indent=2, sort_keys=True) + "\n")
        (out_dir / "limits.json").write_text(json.dumps(limits_summary, indent=2, sort_keys=True) + "\n")
        (out_dir / "decision.json").write_text(
            json.dumps(
                {"status": status, "violations": violations, "overrides": override_notes},
                indent=2,
                sort_keys=True,
            )
            + "\n"
        )
        (out_dir / "capacity.yml.redacted").write_text(json.dumps(capacity, indent=2, sort_keys=True) + "\n")
        (out_dir / "report.md").write_text(
            "# Substrate Capacity Guard\n\n"
            f"Tenant: {tenant_id}\n\n"
            f"Status: {status}\n\n"
            f"Violations: {', '.join(violations) if violations else 'none'}\n\n"
            f"Overrides: {', '.join(override_notes) if override_notes else 'none'}\n"
        )

        manifest_path = out_dir / "manifest.sha256"
        files = sorted([p for p in out_dir.rglob("*") if p.is_file() and p.name != "manifest.sha256"])
        with manifest_path.open("w") as handle:
            for file in files:
                digest = file.read_bytes()
                import hashlib
                sha = hashlib.sha256(digest).hexdigest()
                handle.write(f"{sha}  {file.relative_to(out_dir)}\n")

if any(r.get("status") == "FAIL" for r in results):
    for r in results:
        print(f"{r['status']} capacity guard: {r['tenant']}")
        for v in r.get("violations", []):
            print(f"- {v}")
    sys.exit(2)

for r in results:
    print(f"{r['status']} capacity guard: {r['tenant']}")
    for v in r.get("violations", []):
        print(f"- {v}")

if any(r.get("status") == "WARN" for r in results):
    sys.exit(0)

sys.exit(0)
PY
