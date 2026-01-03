#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

schema_path="${FABRIC_REPO_ROOT}/contracts/incidents/incident.schema.json"

if [[ ! -f "${schema_path}" ]]; then
  echo "ERROR: incident schema missing: ${schema_path}" >&2
  exit 1
fi

files=()

if [[ -n "${INCIDENT_PATH:-}" ]]; then
  files=("${INCIDENT_PATH}")
else
  incident_dir="${INCIDENT_DIR:-}"
  if [[ -z "${incident_dir}" ]]; then
    if [[ -z "${INCIDENT_ID:-}" ]]; then
      echo "ERROR: INCIDENT_PATH or INCIDENT_DIR or INCIDENT_ID is required" >&2
      exit 2
    fi
    incident_dir="${FABRIC_REPO_ROOT}/evidence/incidents/${INCIDENT_ID}"
  fi

  if [[ ! -d "${incident_dir}" ]]; then
    echo "ERROR: incident dir not found: ${incident_dir}" >&2
    exit 1
  fi

  if [[ -f "${incident_dir}/open.json" ]]; then
    files+=("${incident_dir}/open.json")
  else
    echo "ERROR: missing incident open.json in ${incident_dir}" >&2
    exit 1
  fi

  if [[ -f "${incident_dir}/close.json" ]]; then
    files+=("${incident_dir}/close.json")
  fi

  if [[ -d "${incident_dir}/updates" ]]; then
    while IFS= read -r file; do
      files+=("${file}")
    done < <(find "${incident_dir}/updates" -type f -name "*.json" -print | sort)
  fi
fi

SCHEMA_PATH="${schema_path}" FILE_LIST="$(printf '%s\n' "${files[@]}")" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

schema_path = Path(os.environ["SCHEMA_PATH"])
files = [Path(p) for p in os.environ["FILE_LIST"].splitlines() if p]

schema = json.loads(schema_path.read_text())

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
    if schema_obj.get("type") == "array":
        item_schema = schema_obj.get("items")
        if item_schema is not None:
            for idx, item in enumerate(data):
                if not validate(item, item_schema, f"{path}[{idx}]"):
                    return False
    return True

ok = True
for file_path in files:
    try:
        data = json.loads(file_path.read_text())
    except json.JSONDecodeError as exc:
        errors.append(f"{file_path}: invalid JSON ({exc})")
        ok = False
        continue
    if not validate(data, schema, file_path.name):
        ok = False

if ok:
    for file_path in files:
        print(f"PASS incident schema: {file_path}")
    sys.exit(0)

for err in errors:
    print(f"FAIL incident schema: {err}")

sys.exit(1)
PY
