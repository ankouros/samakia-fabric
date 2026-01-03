#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: required file missing: ${path}" >&2
    exit 1
  fi
}

qdrant_file="${FABRIC_REPO_ROOT}/contracts/ai/qdrant.yml"
qdrant_schema="${FABRIC_REPO_ROOT}/contracts/ai/qdrant.schema.json"

require_file "${qdrant_file}"
require_file "${qdrant_schema}"

QDRANT_FILE="${qdrant_file}" QDRANT_SCHEMA="${qdrant_schema}" python3 - <<'PY'
import json
import os
import re

try:
    import yaml
    import jsonschema
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for qdrant policy: {exc}")

qdrant_file = os.environ["QDRANT_FILE"]
qdrant_schema = os.environ["QDRANT_SCHEMA"]

with open(qdrant_schema, "r", encoding="utf-8") as handle:
    schema = json.load(handle)
with open(qdrant_file, "r", encoding="utf-8") as handle:
    payload = yaml.safe_load(handle)

jsonschema.validate(instance=payload, schema=schema)

base_url = payload.get("base_url", "")
if not re.match(r"^https?://(192\.168\.|10\.)", base_url):
    raise SystemExit(f"ERROR: qdrant base_url must be internal (got {base_url})")

auth = payload.get("auth", {})
if auth.get("mode") == "token" and not auth.get("token_ref"):
    raise SystemExit("ERROR: auth.mode=token requires token_ref")

isolation = payload.get("tenant_isolation", {})
if isolation.get("mode") != "collection-per-tenant":
    raise SystemExit("ERROR: tenant_isolation.mode must be collection-per-tenant")
if isolation.get("platform_collection") != "kb_platform":
    raise SystemExit("ERROR: platform_collection must be kb_platform")
if isolation.get("tenant_prefix") != "kb_tenant_":
    raise SystemExit("ERROR: tenant_prefix must be kb_tenant_")

print("PASS: AI qdrant contract enforced")
PY

echo "OK: AI qdrant policy checks passed"
