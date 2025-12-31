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

tenants_root = Path(os.environ["TENANTS_ROOT"])
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


for tenant_dir in tenants_root.rglob("tenant.yml"):
    base = tenant_dir.parent
    policies_path = base / "policies.yml"
    quotas_path = base / "quotas.yml"
    endpoints_path = base / "endpoints.yml"

    if not policies_path.exists():
        errors.append(f"{base}: missing policies.yml")
        continue

    policies = load_json(policies_path)
    if not policies:
        continue

    spec = policies.get("spec", {})
    allowed = spec.get("allowed_consumers", [])
    if not allowed:
        errors.append(f"{policies_path}: allowed_consumers is empty")
        continue
    if not set(allowed).issubset(allowed_consumers):
        errors.append(f"{policies_path}: allowed_consumers contains unknown values")

    variants = spec.get("allowed_variants", {})
    if not isinstance(variants, dict):
        errors.append(f"{policies_path}: allowed_variants must be an object")
        variants = {}
    for consumer in allowed:
        allowed_variants = variants.get(consumer)
        if not allowed_variants:
            errors.append(f"{policies_path}: allowed_variants missing for {consumer}")
        else:
            for variant in allowed_variants:
                if variant not in {"single", "cluster"}:
                    errors.append(f"{policies_path}: invalid variant '{variant}' for {consumer}")

    for key in ("prod_requirements", "execute_guards"):
        if key not in spec:
            errors.append(f"{policies_path}: missing {key}")

    if quotas_path.exists():
        quotas = load_json(quotas_path)
        if quotas:
            quota_spec = quotas.get("spec", {})
            for consumer in allowed:
                if consumer not in quota_spec:
                    errors.append(f"{quotas_path}: missing quota for {consumer}")
    else:
        errors.append(f"{base}: missing quotas.yml")

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
        errors.append(f"{base}: missing endpoints.yml")

if errors:
    for err in errors:
        print(f"FAIL policies: {err}")
    sys.exit(1)

for tenant_dir in tenants_root.rglob("tenant.yml"):
    print(f"PASS policies: {tenant_dir}")
PY
