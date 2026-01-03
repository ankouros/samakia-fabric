#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

provider_file="${PROVIDER_FILE:-${FABRIC_REPO_ROOT}/contracts/ai/provider.yml}"
routing_file="${ROUTING_FILE:-${FABRIC_REPO_ROOT}/contracts/ai/routing.yml}"
provider_schema="${PROVIDER_SCHEMA:-${FABRIC_REPO_ROOT}/contracts/ai/provider.schema.json}"
routing_schema="${ROUTING_SCHEMA:-${FABRIC_REPO_ROOT}/contracts/ai/routing.schema.json}"

usage() {
  cat >&2 <<'EOT'
Usage: validate-config.sh [--provider <path>] [--routing <path>]

Validates AI provider and routing contracts against their schemas.
EOT
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      provider_file="$2"
      shift 2
      ;;
    --routing)
      routing_file="$2"
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

if [[ ! -f "${provider_file}" ]]; then
  echo "ERROR: provider contract not found: ${provider_file}" >&2
  exit 1
fi

if [[ ! -f "${routing_file}" ]]; then
  echo "ERROR: routing contract not found: ${routing_file}" >&2
  exit 1
fi

if [[ ! -f "${provider_schema}" ]]; then
  echo "ERROR: provider schema not found: ${provider_schema}" >&2
  exit 1
fi

if [[ ! -f "${routing_schema}" ]]; then
  echo "ERROR: routing schema not found: ${routing_schema}" >&2
  exit 1
fi

PROVIDER_FILE="${provider_file}" ROUTING_FILE="${routing_file}" \
PROVIDER_SCHEMA="${provider_schema}" ROUTING_SCHEMA="${routing_schema}" python3 - <<'PY'
import json
import os
import sys

try:
    import yaml
    import jsonschema
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for validation: {exc}")

provider_file = os.environ["PROVIDER_FILE"]
routing_file = os.environ["ROUTING_FILE"]
provider_schema = os.environ["PROVIDER_SCHEMA"]
routing_schema = os.environ["ROUTING_SCHEMA"]

with open(provider_schema, "r", encoding="utf-8") as handle:
    provider_schema_data = json.load(handle)
with open(routing_schema, "r", encoding="utf-8") as handle:
    routing_schema_data = json.load(handle)

with open(provider_file, "r", encoding="utf-8") as handle:
    provider_payload = yaml.safe_load(handle)
with open(routing_file, "r", encoding="utf-8") as handle:
    routing_payload = yaml.safe_load(handle)

jsonschema.validate(instance=provider_payload, schema=provider_schema_data)
jsonschema.validate(instance=routing_payload, schema=routing_schema_data)

print(f"PASS provider schema: {provider_file}")
print(f"PASS routing schema: {routing_file}")
PY
