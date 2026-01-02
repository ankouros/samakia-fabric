#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      out="$2"
      shift 2
      ;;
    -h|--help)
      echo "usage: rotate-plan.sh [--out <path>]" >&2
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
 done

tenant_filter="${TENANT:-all}"
rotation_stamp="${ROTATION_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"

bindings_root="${FABRIC_REPO_ROOT}/contracts/bindings/tenants"
mapfile -t bindings < <(find "${bindings_root}" -type f -name "*.binding.yml" -print | sort)
if [[ ${#bindings[@]} -eq 0 ]]; then
  echo "ERROR: no binding contracts found under ${bindings_root}" >&2
  exit 1
fi

plan_json=$(BINDINGS_LIST="$(printf '%s\n' "${bindings[@]}")" TENANT_FILTER="${tenant_filter}" ROTATION_STAMP="${rotation_stamp}" python3 - <<'PY'
import json
import os
from pathlib import Path
import yaml

bindings = [Path(p) for p in os.environ.get("BINDINGS_LIST", "").splitlines() if p]
flt = os.environ.get("TENANT_FILTER", "all")
stamp = os.environ.get("ROTATION_STAMP")

entries = []
for binding in bindings:
    data = yaml.safe_load(binding.read_text())
    meta = data.get("metadata", {})
    tenant = meta.get("tenant") or ""
    env = meta.get("env") or ""
    if flt != "all" and tenant != flt:
        continue
    for consumer in data.get("spec", {}).get("consumers", []):
        rotation = consumer.get("rotation_policy", {})
        if rotation.get("enabled") is not True:
            continue
        secret_ref = consumer.get("secret_ref") or ""
        secret_shape = consumer.get("secret_shape") or ""
        provider = consumer.get("provider") or ""
        if not secret_ref:
            continue
        new_ref = f"{secret_ref}/rotations/{stamp}"
        entries.append({
            "tenant": tenant,
            "env": env,
            "secret_ref": secret_ref,
            "new_secret_ref": new_ref,
            "secret_shape": secret_shape,
            "provider": provider,
            "rotation_policy": rotation,
        })

payload = {"rotation_stamp": stamp, "entries": entries}
print(json.dumps(payload, indent=2, sort_keys=True))
PY
)

if [[ -n "${out}" ]]; then
  printf '%s\n' "${plan_json}" > "${out}"
else
  printf '%s\n' "${plan_json}"
fi
