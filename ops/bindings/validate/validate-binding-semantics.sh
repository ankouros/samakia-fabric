#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

bindings_root="${FABRIC_REPO_ROOT}/contracts/bindings/tenants"
if [[ ! -d "${bindings_root}" ]]; then
  echo "ERROR: bindings root not found: ${bindings_root}" >&2
  exit 1
fi

mapfile -t bindings < <(find "${bindings_root}" -type f -name "*.binding.yml" -print | sort)
if [[ ${#bindings[@]} -eq 0 ]]; then
  echo "ERROR: no binding contracts found under ${bindings_root}" >&2
  exit 1
fi

BINDINGS_LIST="$(printf '%s\n' "${bindings[@]}")" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" python3 - <<'PY'
import json
import os
import re
import sys
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])
bindings = [Path(p) for p in os.environ["BINDINGS_LIST"].splitlines() if p]

tenants_root = root / "contracts" / "tenants"

allowed_types = {"database", "mq", "cache", "vector"}
provider_map = {
    "database": {"postgres", "mariadb"},
    "mq": {"rabbitmq"},
    "cache": {"dragonfly"},
    "vector": {"qdrant"},
}
consumer_map = {
    "database": "database",
    "mq": "message-queue",
    "cache": "cache",
    "vector": "vector",
}

errors = []


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        errors.append(f"{path}: invalid JSON ({exc})")
        return None


for binding_path in bindings:
    data = load_json(binding_path)
    if not data:
        continue

    meta = data.get("metadata", {})
    tenant = meta.get("tenant")
    env = meta.get("env")
    workload_id = meta.get("workload_id")
    workload_type = meta.get("workload_type")

    if not tenant:
        errors.append(f"{binding_path}: metadata.tenant missing")
        continue

    tenant_dir = tenants_root / tenant
    if not tenant_dir.exists():
        tenant_dir = tenants_root / "examples" / tenant
    tenant_file = tenant_dir / "tenant.yml"
    if not tenant_dir.exists():
        errors.append(f"{binding_path}: tenant directory missing {tenant_dir}")
        continue

    tenant_data = load_json(tenant_file) if tenant_file.exists() else None
    if not tenant_data:
        errors.append(f"{binding_path}: tenant.yml missing or invalid")
        continue

    tenant_meta = tenant_data.get("metadata", {})
    if tenant_meta.get("id") != tenant:
        errors.append(f"{binding_path}: tenant.yml metadata.id mismatch")

    envs = tenant_data.get("spec", {}).get("environments", {})
    if not env or not isinstance(envs, dict) or not envs.get(env, False):
        errors.append(f"{binding_path}: env '{env}' not enabled in tenant.yml")

    if not workload_id:
        errors.append(f"{binding_path}: workload_id missing")
    else:
        filename = binding_path.name
        expected_name = filename
        if filename.endswith(".binding.yml"):
            expected_name = filename[:-len(".binding.yml")]
        if expected_name != workload_id:
            errors.append(f"{binding_path}: workload_id '{workload_id}' must match filename '{expected_name}'")

    if workload_type not in {"k8s", "vm", "job", "external"}:
        errors.append(f"{binding_path}: workload_type '{workload_type}' invalid")

    consumers = data.get("spec", {}).get("consumers", [])
    if not isinstance(consumers, list) or not consumers:
        errors.append(f"{binding_path}: spec.consumers missing or empty")
        continue

    for idx, consumer in enumerate(consumers):
        if not isinstance(consumer, dict):
            errors.append(f"{binding_path}: consumer[{idx}] must be object")
            continue
        c_type = consumer.get("type")
        provider = consumer.get("provider")
        variant = consumer.get("variant")
        ref = consumer.get("ref")
        access_mode = consumer.get("access_mode")
        secret_ref = consumer.get("secret_ref")
        connection_profile = consumer.get("connection_profile", {})
        lifecycle = consumer.get("lifecycle", {})

        if c_type not in allowed_types:
            errors.append(f"{binding_path}: consumer[{idx}].type '{c_type}' invalid")
            continue
        if provider not in provider_map.get(c_type, set()):
            errors.append(f"{binding_path}: consumer[{idx}] provider '{provider}' not allowed for {c_type}")

        if variant not in {"single", "cluster"}:
            errors.append(f"{binding_path}: consumer[{idx}].variant '{variant}' invalid")

        if access_mode not in {"read", "readwrite"}:
            errors.append(f"{binding_path}: consumer[{idx}].access_mode '{access_mode}' invalid")

        if not isinstance(secret_ref, str) or not secret_ref:
            errors.append(f"{binding_path}: consumer[{idx}].secret_ref missing")
        elif not secret_ref.startswith(f"tenants/{tenant}/"):
            errors.append(f"{binding_path}: consumer[{idx}].secret_ref must start with tenants/{tenant}/")

        if not isinstance(ref, str) or not ref:
            errors.append(f"{binding_path}: consumer[{idx}].ref missing")
            continue
        ref_path = (root / ref).resolve()
        if root not in ref_path.parents and ref_path != root:
            errors.append(f"{binding_path}: consumer[{idx}].ref escapes repo")
            continue
        if not ref_path.exists():
            errors.append(f"{binding_path}: consumer[{idx}].ref not found {ref_path}")
            continue
        if ref_path.name != "enabled.yml":
            errors.append(f"{binding_path}: consumer[{idx}].ref must point to enabled.yml")

        ref_posix = ref_path.as_posix()
        if f"/contracts/tenants/{tenant}/" not in ref_posix and f"/contracts/tenants/examples/{tenant}/" not in ref_posix:
            errors.append(f"{binding_path}: consumer[{idx}].ref must reference tenant {tenant}")

        enabled = load_json(ref_path)
        if enabled:
            expected_consumer = consumer_map.get(c_type)
            if enabled.get("consumer") != expected_consumer:
                errors.append(
                    f"{binding_path}: consumer[{idx}] ref consumer '{enabled.get('consumer')}' != '{expected_consumer}'"
                )
            executor = enabled.get("executor", {})
            if executor.get("provider") != provider:
                errors.append(
                    f"{binding_path}: consumer[{idx}] provider '{provider}' != enabled '{executor.get('provider')}'"
                )
            if enabled.get("variant") != variant:
                errors.append(
                    f"{binding_path}: consumer[{idx}] variant '{variant}' != enabled '{enabled.get('variant')}'"
                )

        if connection_profile.get("tls_required") is not True:
            errors.append(f"{binding_path}: consumer[{idx}].connection_profile.tls_required must be true")

        if lifecycle.get("rotate_credentials") not in {"manual", "scheduled"}:
            errors.append(f"{binding_path}: consumer[{idx}].lifecycle.rotate_credentials invalid")
        if not isinstance(lifecycle.get("revoke_on_delete"), bool):
            errors.append(f"{binding_path}: consumer[{idx}].lifecycle.revoke_on_delete must be boolean")

if errors:
    for err in errors:
        print(f"FAIL semantics: {err}")
    sys.exit(1)

for binding_path in bindings:
    print(f"PASS semantics: {binding_path}")
PY
