#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

json_export() {
  local entry_file="$1"
  if [[ ! -f "${entry_file}" ]]; then
    echo "ERROR: entry file not found: ${entry_file}" >&2
    exit 2
  fi
  python3 - "${entry_file}" <<'PY'
import json
import sys
from pathlib import Path

entry_path = Path(sys.argv[1])
raw = entry_path.read_text()
entry = json.loads(raw)

mapping = {
    "TENANT": entry.get("tenant"),
    "ENV": entry.get("env"),
    "WORKLOAD_ID": entry.get("workload_id"),
    "CONSUMER_TYPE": entry.get("consumer", {}).get("type"),
    "PROVIDER": entry.get("consumer", {}).get("provider"),
    "VARIANT": entry.get("consumer", {}).get("variant"),
    "ACCESS_MODE": entry.get("consumer", {}).get("access_mode"),
    "SECRET_REF": entry.get("consumer", {}).get("secret_ref"),
    "SECRET_SHAPE": entry.get("consumer", {}).get("secret_shape"),
    "ENDPOINT_HOST": entry.get("endpoint", {}).get("host"),
    "ENDPOINT_PORT": entry.get("endpoint", {}).get("port"),
    "ENDPOINT_PROTOCOL": entry.get("endpoint", {}).get("protocol"),
    "TLS_REQUIRED": entry.get("endpoint", {}).get("tls_required"),
    "CONNECT_TIMEOUT_MS": entry.get("connection_profile", {}).get("connect_timeout_ms"),
    "READ_TIMEOUT_MS": entry.get("connection_profile", {}).get("read_timeout_ms"),
}

resources = entry.get("resources", {})
for key, value in resources.items():
    if isinstance(value, list):
        value = ",".join([str(v) for v in value])
    mapping[f"RESOURCE_{key.upper()}"] = value

for key in sorted(mapping.keys()):
    value = mapping[key]
    if value is None:
        continue
    if isinstance(value, bool):
        value = "true" if value else "false"
    print(f"{key}={value}")
PY
}
