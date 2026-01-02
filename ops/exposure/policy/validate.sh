#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  echo "usage: validate.sh [--policy <path>]" >&2
}

policy_file="${POLICY_FILE:-${FABRIC_REPO_ROOT}/contracts/exposure/exposure-policy.yml}"
schema_file="${FABRIC_REPO_ROOT}/contracts/exposure/exposure-policy.schema.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy)
      policy_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ ! -f "${policy_file}" ]]; then
  echo "ERROR: policy file not found: ${policy_file}" >&2
  exit 1
fi

if [[ ! -f "${schema_file}" ]]; then
  echo "ERROR: policy schema not found: ${schema_file}" >&2
  exit 1
fi

POLICY_FILE="${policy_file}" SCHEMA_FILE="${schema_file}" python3 - <<'PY'
import json
import os
import sys

try:
    import yaml
    import jsonschema
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for validation: {exc}")

policy_path = os.environ["POLICY_FILE"]
schema_path = os.environ["SCHEMA_FILE"]

with open(schema_path, "r", encoding="utf-8") as handle:
    schema = json.load(handle)

with open(policy_path, "r", encoding="utf-8") as handle:
    payload = yaml.safe_load(handle)

jsonschema.validate(instance=payload, schema=schema)
print(f"PASS policy schema: {policy_path}")
PY
