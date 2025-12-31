#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

TENANTS_ROOT="${FABRIC_REPO_ROOT}/contracts/tenants"

if [[ ! -d "${TENANTS_ROOT}" ]]; then
  echo "ERROR: tenants directory not found: ${TENANTS_ROOT}" >&2
  exit 1
fi

TENANTS_ROOT="${TENANTS_ROOT}" python3 - <<'PY'
import json
import os
import re
import sys
from pathlib import Path

root = Path(os.environ["TENANTS_ROOT"])
allowed_consumers = {"database", "message-queue", "cache", "vector", "kubernetes"}
secret_pattern = re.compile(
    r"(password|token|secret|BEGIN (RSA|OPENSSH)|AKIA[0-9A-Z]{12,})",
    re.IGNORECASE,
)

errors = []

def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        errors.append(f"{path}: invalid JSON ({exc})")
        return None

# Tenant directories
for tenant_file in root.rglob("tenant.yml"):
    tenant_dir = tenant_file.parent
    tenant = load_json(tenant_file)
    if not tenant:
        continue
    tenant_id = tenant.get("metadata", {}).get("id", "")
    rel = tenant_dir.relative_to(root)
    if "examples" in rel.parts:
        dirname = tenant_dir.name
        if tenant_id != dirname:
            errors.append(f"{tenant_file}: metadata.id '{tenant_id}' does not match folder '{dirname}'")
        if not re.match(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", tenant_id):
            errors.append(f"{tenant_file}: metadata.id '{tenant_id}' is not a dns-safe slug")

    policies_path = tenant_dir / "policies.yml"
    quotas_path = tenant_dir / "quotas.yml"
    endpoints_path = tenant_dir / "endpoints.yml"

    if not policies_path.exists():
        errors.append(f"{tenant_dir}: missing policies.yml")
        continue

    policies = load_json(policies_path)
    if not policies:
        continue

    allowed = policies.get("spec", {}).get("allowed_consumers", [])
    if not allowed:
        errors.append(f"{policies_path}: allowed_consumers is empty")
        continue
    if not set(allowed).issubset(allowed_consumers):
        bad = set(allowed) - allowed_consumers
        errors.append(f"{policies_path}: unknown allowed_consumers {sorted(bad)}")

    allowed_variants = policies.get("spec", {}).get("allowed_variants", {})
    if not isinstance(allowed_variants, dict):
        errors.append(f"{policies_path}: allowed_variants must be an object")
        allowed_variants = {}
    extra_keys = set(allowed_variants.keys()) - set(allowed)
    if extra_keys:
        errors.append(f"{policies_path}: allowed_variants keys not in allowed_consumers {sorted(extra_keys)}")
    for consumer in allowed:
        variants = allowed_variants.get(consumer, [])
        if not variants:
            errors.append(f"{policies_path}: allowed_variants missing for consumer '{consumer}'")

    if quotas_path.exists():
        quotas = load_json(quotas_path)
        if quotas:
            quota_keys = set(quotas.get("spec", {}).keys())
            extra = quota_keys - set(allowed)
            if extra:
                errors.append(f"{quotas_path}: quota keys not in allowed_consumers {sorted(extra)}")
    else:
        errors.append(f"{tenant_dir}: missing quotas.yml")

    if endpoints_path.exists():
        endpoints = load_json(endpoints_path)
        if endpoints:
            for ep in endpoints.get("spec", {}).get("endpoints", []):
                for key, val in ep.items():
                    if key == "secret_ref":
                        continue
                    if isinstance(val, str) and secret_pattern.search(val):
                        errors.append(f"{endpoints_path}: endpoint field '{key}' contains secret-like value")
    else:
        errors.append(f"{tenant_dir}: missing endpoints.yml")

    consumers_dir = tenant_dir / "consumers"
    ready_files = list(consumers_dir.rglob("ready.yml")) if consumers_dir.exists() else []
    enabled_files = list(consumers_dir.rglob("enabled.yml")) if consumers_dir.exists() else []
    if not ready_files:
        errors.append(f"{tenant_dir}: no consumer ready.yml files found")
    for ready_file in ready_files:
        consumer_dir = ready_file.parent.name
        binding = load_json(ready_file)
        if not binding:
            continue
        spec = binding.get("spec", {})
        consumer = spec.get("consumer", "")
        if consumer != consumer_dir:
            errors.append(f"{ready_file}: spec.consumer '{consumer}' does not match folder '{consumer_dir}'")
        if consumer not in allowed:
            errors.append(f"{ready_file}: consumer '{consumer}' not in allowed_consumers")
        variant = spec.get("variant")
        if variant not in {"single", "cluster"}:
            errors.append(f"{ready_file}: invalid variant '{variant}'")
        if consumer in allowed_variants and variant not in allowed_variants.get(consumer, []):
            errors.append(f"{ready_file}: variant '{variant}' not allowed for consumer '{consumer}'")
        if spec.get("ha_ready") is not True:
            errors.append(f"{ready_file}: ha_ready must be true")
        dr = spec.get("dr_testcases", [])
        if not isinstance(dr, list) or not dr:
            errors.append(f"{ready_file}: dr_testcases must be a non-empty list")

    for enabled_file in enabled_files:
        consumer_dir = enabled_file.parent.name
        binding = load_json(enabled_file)
        if not binding:
            continue
        spec = binding.get("spec", {})
        consumer = spec.get("consumer", "")
        if consumer != consumer_dir:
            errors.append(f"{enabled_file}: spec.consumer '{consumer}' does not match folder '{consumer_dir}'")
        if consumer not in allowed:
            errors.append(f"{enabled_file}: consumer '{consumer}' not in allowed_consumers")
        variant = spec.get("variant")
        if variant not in {"single", "cluster"}:
            errors.append(f"{enabled_file}: invalid variant '{variant}'")
        if consumer in allowed_variants and variant not in allowed_variants.get(consumer, []):
            errors.append(f"{enabled_file}: variant '{variant}' not allowed for consumer '{consumer}'")
        if spec.get("ha_ready") is not True:
            errors.append(f"{enabled_file}: ha_ready must be true")
        mode = spec.get("mode")
        if mode not in {"dry-run", "execute"}:
            errors.append(f"{enabled_file}: mode must be dry-run or execute")
        endpoint_ref = spec.get("endpoint_ref")
        if not isinstance(endpoint_ref, str) or not endpoint_ref.strip():
            errors.append(f"{enabled_file}: endpoint_ref must be a non-empty string")
        secret_ref = spec.get("secret_ref")
        if not isinstance(secret_ref, str) or not secret_ref.strip():
            errors.append(f"{enabled_file}: secret_ref must be a non-empty string")
        backup_target = spec.get("backup_target")
        if not isinstance(backup_target, str) or not backup_target.strip():
            errors.append(f"{enabled_file}: backup_target must be a non-empty string")
        restore_tests = spec.get("restore_testcases", [])
        if not isinstance(restore_tests, list) or not restore_tests:
            errors.append(f"{enabled_file}: restore_testcases must be a non-empty list")
        dr = spec.get("dr_testcases", [])
        if not isinstance(dr, list) or not dr:
            errors.append(f"{enabled_file}: dr_testcases must be a non-empty list")
        owner = spec.get("owner", {})
        if owner.get("tenant_id") != tenant_id or owner.get("consumer") != consumer:
            errors.append(f"{enabled_file}: owner must match tenant_id and consumer")

if errors:
    for err in errors:
        print(f"FAIL semantics: {err}")
    sys.exit(1)

for tenant_file in root.rglob("tenant.yml"):
    print(f"PASS semantics: {tenant_file}")

sys.exit(0)
PY
