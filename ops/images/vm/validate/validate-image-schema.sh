#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

schema_path="${FABRIC_REPO_ROOT}/contracts/images/vm/_schema/vm-image-contract.schema.json"

if [[ ! -f "$schema_path" ]]; then
  echo "ERROR: schema not found: $schema_path" >&2
  exit 1
fi

python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

schema_path = Path(os.environ["FABRIC_REPO_ROOT"]) / "contracts/images/vm/_schema/vm-image-contract.schema.json"
contracts = [
    Path(os.environ["FABRIC_REPO_ROOT"]) / "contracts/images/vm/ubuntu-24.04/v1/image.yml",
    Path(os.environ["FABRIC_REPO_ROOT"]) / "contracts/images/vm/debian-12/v1/image.yml",
]

schema = json.loads(schema_path.read_text())


def err(msg):
    print(msg, file=sys.stderr)


def type_ok(value, expected):
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int)
    if expected == "boolean":
        return isinstance(value, bool)
    return True


def validate(data, schema_obj, path="$"):
    if "type" in schema_obj:
        if not type_ok(data, schema_obj["type"]):
            err(f"{path}: expected {schema_obj['type']}")
            return False
    if "const" in schema_obj:
        if data != schema_obj["const"]:
            err(f"{path}: expected const {schema_obj['const']}")
            return False
    if "enum" in schema_obj:
        if data not in schema_obj["enum"]:
            err(f"{path}: value {data} not in {schema_obj['enum']}")
            return False
    if schema_obj.get("type") == "object":
        required = schema_obj.get("required", [])
        for key in required:
            if key not in data:
                err(f"{path}: missing required key {key}")
                return False
        props = schema_obj.get("properties", {})
        for key, val in data.items():
            if key in props:
                if not validate(val, props[key], f"{path}.{key}"):
                    return False
    if schema_obj.get("type") == "array":
        item_schema = schema_obj.get("items")
        if item_schema is not None:
            for idx, item in enumerate(data):
                if not validate(item, item_schema, f"{path}[{idx}]"):
                    return False
    return True

ok = True
for contract in contracts:
    data = json.loads(contract.read_text())
    if not validate(data, schema, f"{contract.name}"):
        ok = False

if not ok:
    sys.exit(1)
PY
