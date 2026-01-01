#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

taxonomy_file="${FABRIC_REPO_ROOT}/contracts/substrate/dr-testcases.yml"

if [[ ! -f "${taxonomy_file}" ]]; then
  echo "ERROR: substrate DR taxonomy missing: ${taxonomy_file}" >&2
  exit 1
fi

TAXONOMY_FILE="${taxonomy_file}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(os.environ["TAXONOMY_FILE"])
errors = []

try:
    data = json.loads(path.read_text())
except json.JSONDecodeError as exc:
    print(f"FAIL taxonomy: {path} invalid JSON ({exc})")
    sys.exit(1)

required_keys = {"common", "database", "message-queue", "cache", "vector", "cluster-only"}
missing = required_keys - set(data.keys())
if missing:
    errors.append(f"missing keys: {sorted(missing)}")

if not isinstance(data.get("common"), list):
    errors.append("common must be a list")

for section in ("database", "message-queue", "cache", "vector"):
    if not isinstance(data.get(section), dict):
        errors.append(f"{section} must be an object")

provider_map = {
    "database": ["postgres", "mariadb"],
    "message-queue": ["rabbitmq"],
    "cache": ["dragonfly"],
    "vector": ["qdrant"],
}

for section, providers in provider_map.items():
    block = data.get(section, {})
    for provider in providers:
        cases = block.get(provider)
        if not isinstance(cases, list):
            errors.append(f"{section}.{provider} must be a list")
        elif not cases:
            errors.append(f"{section}.{provider} must not be empty")
        elif any(not isinstance(item, str) for item in cases):
            errors.append(f"{section}.{provider} entries must be strings")

cluster_only = data.get("cluster-only")
if not isinstance(cluster_only, list):
    errors.append("cluster-only must be a list")

if errors:
    for err in errors:
        print(f"FAIL taxonomy: {path}: {err}")
    sys.exit(1)

print(f"PASS taxonomy: {path}")
PY
