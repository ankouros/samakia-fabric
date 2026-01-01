#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

tenants_root="${FABRIC_REPO_ROOT}/contracts/tenants"
taxonomy_file="${FABRIC_REPO_ROOT}/contracts/substrate/dr-testcases.yml"

if [[ ! -d "${tenants_root}" ]]; then
  echo "ERROR: tenants directory not found: ${tenants_root}" >&2
  exit 1
fi

if [[ ! -f "${taxonomy_file}" ]]; then
  echo "ERROR: substrate DR taxonomy missing: ${taxonomy_file}" >&2
  exit 1
fi

TENANTS_ROOT="${tenants_root}" TAXONOMY_FILE="${taxonomy_file}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

tenants_root = Path(os.environ["TENANTS_ROOT"])
taxonomy_path = Path(os.environ["TAXONOMY_FILE"])

errors = []

provider_map = {
    "database": ["postgres", "mariadb"],
    "message-queue": ["rabbitmq"],
    "cache": ["dragonfly"],
    "vector": ["qdrant"],
}


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        errors.append(f"{path}: invalid JSON ({exc})")
        return None


taxonomy = load_json(taxonomy_path)
if not isinstance(taxonomy, dict):
    errors.append(f"{taxonomy_path}: taxonomy must be an object")
    taxonomy = {}

common_cases = set(taxonomy.get("common", []) if isinstance(taxonomy.get("common"), list) else [])
cluster_cases = set(taxonomy.get("cluster-only", []) if isinstance(taxonomy.get("cluster-only"), list) else [])


def allowed_cases(consumer, provider, variant):
    allowed = set(common_cases)
    section = taxonomy.get(consumer, {})
    if isinstance(section, dict):
        provider_cases = section.get(provider, [])
        if isinstance(provider_cases, list):
            allowed.update(provider_cases)
    if variant == "cluster":
        allowed.update(cluster_cases)
    return allowed


enabled_files = []
for consumer in provider_map:
    enabled_files.extend(tenants_root.rglob(f"consumers/{consumer}/enabled.yml"))

if not enabled_files:
    errors.append("no enabled.yml files found for substrate consumers")

for enabled in enabled_files:
    binding = load_json(enabled)
    if not binding:
        continue

    consumer = binding.get("consumer")
    if consumer not in provider_map:
        errors.append(f"{enabled}: consumer '{consumer}' not supported")
        continue

    if enabled.parent.name != consumer:
        errors.append(f"{enabled}: consumer '{consumer}' does not match folder '{enabled.parent.name}'")

    variant = binding.get("variant")
    if variant not in {"single", "cluster"}:
        errors.append(f"{enabled}: variant must be single or cluster")

    if binding.get("ha_ready") is not True:
        errors.append(f"{enabled}: ha_ready must be true")

    executor = binding.get("executor", {})
    provider = executor.get("provider")
    if provider not in provider_map.get(consumer, []):
        errors.append(f"{enabled}: executor.provider '{provider}' not allowed for consumer '{consumer}'")

    mode = executor.get("mode")
    if mode not in {"dry-run", "execute"}:
        errors.append(f"{enabled}: executor.mode must be dry-run or execute")

    plan_only = executor.get("plan_only")
    if not isinstance(plan_only, bool):
        errors.append(f"{enabled}: executor.plan_only must be boolean")

    dr = binding.get("dr", {})
    required = dr.get("required_testcases", [])
    if not isinstance(required, list) or not required:
        errors.append(f"{enabled}: dr.required_testcases must be a non-empty list")
    else:
        allowed = allowed_cases(consumer, provider, variant)
        unknown = [case for case in required if case not in allowed]
        if unknown:
            errors.append(f"{enabled}: unknown dr.required_testcases {unknown}")

    endpoints = binding.get("endpoints", {})
    host = endpoints.get("host")
    port = endpoints.get("port")
    protocol = endpoints.get("protocol")
    tls_required = endpoints.get("tls_required")

    if not isinstance(host, str) or not host.strip():
        errors.append(f"{enabled}: endpoints.host must be a non-empty string")
    if not isinstance(port, int):
        errors.append(f"{enabled}: endpoints.port must be an integer")
    if protocol not in {"tcp", "https"}:
        errors.append(f"{enabled}: endpoints.protocol must be tcp or https")
    if not isinstance(tls_required, bool):
        errors.append(f"{enabled}: endpoints.tls_required must be boolean")

    secret_ref = binding.get("secret_ref")
    if not isinstance(secret_ref, str) or not secret_ref.strip():
        errors.append(f"{enabled}: secret_ref must be a non-empty string")

    resources = binding.get("resources")
    if not isinstance(resources, dict):
        errors.append(f"{enabled}: resources must be an object")

if errors:
    for err in errors:
        print(f"FAIL substrate: {err}")
    sys.exit(1)

for enabled in enabled_files:
    print(f"PASS substrate: {enabled}")
PY
