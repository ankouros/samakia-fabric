#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

schema_path="${FABRIC_REPO_ROOT}/contracts/tenants/_schema/capacity.schema.json"
contracts_root="${FABRIC_REPO_ROOT}/contracts/tenants"

if [[ ! -f "${schema_path}" ]]; then
  echo "ERROR: capacity schema missing: ${schema_path}" >&2
  exit 1
fi

mapfile -t capacity_files < <(find "${contracts_root}" -type f -name "capacity.yml" -print | sort)

if [[ ${#capacity_files[@]} -eq 0 ]]; then
  echo "ERROR: no capacity.yml files found under ${contracts_root}" >&2
  exit 1
fi

SCHEMA_PATH="${schema_path}" CAPACITY_LIST="$(printf '%s\n' "${capacity_files[@]}")" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

schema_path = Path(os.environ["SCHEMA_PATH"])
capacity_files = [Path(p) for p in os.environ["CAPACITY_LIST"].splitlines() if p]

errors = []


def type_ok(value, expected):
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int)
    if expected == "number":
        return isinstance(value, (int, float))
    if expected == "boolean":
        return isinstance(value, bool)
    return True


def validate(data, schema_obj, path="$"):
    if "type" in schema_obj:
        if not type_ok(data, schema_obj["type"]):
            errors.append(f"{path}: expected {schema_obj['type']}")
            return False
    if "const" in schema_obj:
        if data != schema_obj["const"]:
            errors.append(f"{path}: expected const {schema_obj['const']}")
            return False
    if "enum" in schema_obj:
        if data not in schema_obj["enum"]:
            errors.append(f"{path}: value {data} not in {schema_obj['enum']}")
            return False
    if "minimum" in schema_obj:
        if isinstance(data, (int, float)) and data < schema_obj["minimum"]:
            errors.append(f"{path}: value {data} below minimum {schema_obj['minimum']}")
            return False
    if schema_obj.get("type") == "object":
        required = schema_obj.get("required", [])
        for key in required:
            if key not in data:
                errors.append(f"{path}: missing required key {key}")
                return False
        props = schema_obj.get("properties", {})
        additional = schema_obj.get("additionalProperties", True)
        if additional is False:
            for key in data:
                if key not in props:
                    errors.append(f"{path}: unknown key {key}")
                    return False
        for key, val in data.items():
            if key in props:
                if not validate(val, props[key], f"{path}.{key}"):
                    return False
            elif isinstance(additional, dict):
                if not validate(val, additional, f"{path}.{key}"):
                    return False
    if schema_obj.get("type") == "array":
        item_schema = schema_obj.get("items")
        if item_schema is not None:
            for idx, item in enumerate(data):
                if not validate(item, item_schema, f"{path}[{idx}]"):
                    return False
    return True

try:
    schema = json.loads(schema_path.read_text())
except json.JSONDecodeError as exc:
    print(f"FAIL capacity schema: {schema_path} invalid JSON ({exc})")
    sys.exit(1)

ok = True
for capacity in capacity_files:
    try:
        data = json.loads(capacity.read_text())
    except json.JSONDecodeError as exc:
        errors.append(f"{capacity}: invalid JSON ({exc})")
        ok = False
        continue
    if not validate(data, schema, capacity.name):
        ok = False

if ok:
    for capacity in capacity_files:
        print(f"PASS capacity schema: {capacity}")
    sys.exit(0)

for err in errors:
    print(f"FAIL capacity schema: {err}")

sys.exit(1)
PY
