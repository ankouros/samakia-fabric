#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

binding_arg=""
out_root="${OUT_ROOT:-${FABRIC_REPO_ROOT}/artifacts/bindings}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binding)
      binding_arg="$2"
      shift 2
      ;;
    --out)
      out_root="$2"
      shift 2
      ;;
    *)
      echo "usage: render-connection-manifest.sh [--binding <path>] [--out <dir>]" >&2
      exit 2
      ;;
  esac
 done

bindings=()
if [[ -n "${binding_arg}" ]]; then
  bindings=("${binding_arg}")
elif [[ "${TENANT:-}" == "all" || -z "${TENANT:-}" ]]; then
  mapfile -t bindings < <(find "${FABRIC_REPO_ROOT}/contracts/bindings/tenants" -type f -name "*.binding.yml" -print | sort)
else
  if [[ -z "${WORKLOAD:-}" ]]; then
    echo "ERROR: WORKLOAD is required when TENANT is set" >&2
    exit 1
  fi
  bindings=("${FABRIC_REPO_ROOT}/contracts/bindings/tenants/${TENANT}/${WORKLOAD}.binding.yml")
fi

if [[ ${#bindings[@]} -eq 0 ]]; then
  echo "ERROR: no binding contracts found" >&2
  exit 1
fi

OUT_ROOT="${out_root}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" BINDINGS_LIST="$(printf '%s\n' "${bindings[@]}")" python3 - <<'PY'
import json
import os
from pathlib import Path
from datetime import datetime, timezone
import hashlib

root = Path(os.environ["FABRIC_REPO_ROOT"])
out_root = Path(os.environ["OUT_ROOT"])
bindings = [Path(p) for p in os.environ["BINDINGS_LIST"].splitlines() if p]

provider_key_map = {
    "database": ["database", "user", "schema"],
    "mq": ["vhost", "user"],
    "cache": ["tenant_key_prefix"],
    "vector": ["collections"],
}


def load_json(path: Path):
    return json.loads(path.read_text())


def sha256_file(path: Path):
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


for binding_path in bindings:
    data = load_json(binding_path)
    meta = data.get("metadata", {})
    spec = data.get("spec", {})
    tenant = meta.get("tenant")
    env = meta.get("env")
    workload_id = meta.get("workload_id")
    workload_type = meta.get("workload_type")

    if not tenant or not workload_id:
        raise SystemExit(f"ERROR: invalid binding metadata in {binding_path}")

    out_dir = out_root / tenant / workload_id
    out_dir.mkdir(parents=True, exist_ok=True)

    consumers_out = []
    env_map = {}
    type_counts = {}

    for consumer in spec.get("consumers", []):
        c_type = consumer.get("type")
        type_counts[c_type] = type_counts.get(c_type, 0) + 1

    type_index = {k: 0 for k in type_counts}

    for consumer in spec.get("consumers", []):
        c_type = consumer.get("type")
        provider = consumer.get("provider")
        variant = consumer.get("variant")
        ref = consumer.get("ref")
        access_mode = consumer.get("access_mode")
        secret_ref = consumer.get("secret_ref")
        connection_profile = consumer.get("connection_profile", {})

        enabled_path = (root / ref).resolve()
        enabled = load_json(enabled_path)
        endpoints = enabled.get("endpoints", {})
        resources = enabled.get("resources", {})

        consumer_entry = {
            "type": c_type,
            "provider": provider,
            "variant": variant,
            "access_mode": access_mode,
            "secret_ref": secret_ref,
            "endpoint": {
                "host": endpoints.get("host"),
                "port": endpoints.get("port"),
                "protocol": endpoints.get("protocol"),
                "tls_required": endpoints.get("tls_required"),
            },
            "connection_profile": connection_profile,
            "resources": resources,
        }
        consumers_out.append(consumer_entry)

        prefix = c_type.upper() if isinstance(c_type, str) else "CONSUMER"
        type_index[prefix.lower()] = type_index.get(prefix.lower(), 0) + 1
        suffix = type_index[prefix.lower()]
        env_prefix = prefix
        if type_counts.get(c_type, 0) > 1:
            env_prefix = f"{prefix}_{suffix}"

        def set_env(key, value):
            if value is None:
                return
            env_map[f"{env_prefix}_{key}"] = str(value)

        set_env("HOST", endpoints.get("host"))
        set_env("PORT", endpoints.get("port"))
        set_env("PROTOCOL", endpoints.get("protocol"))
        set_env("TLS_REQUIRED", "true" if endpoints.get("tls_required") else "false")
        set_env("SECRET_REF", secret_ref)
        set_env("PROVIDER", provider)
        set_env("VARIANT", variant)
        set_env("ACCESS_MODE", access_mode)

        if connection_profile:
            set_env("CONNECT_TIMEOUT_MS", connection_profile.get("connect_timeout_ms"))
            set_env("READ_TIMEOUT_MS", connection_profile.get("read_timeout_ms"))

        for field in provider_key_map.get(c_type, []):
            value = resources.get(field)
            if isinstance(value, list):
                value = ",".join([str(v) for v in value])
            set_env(field.upper(), value)

    manifest = {
        "tenant": tenant,
        "env": env,
        "workload_id": workload_id,
        "workload_type": workload_type,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "consumers": consumers_out,
    }

    json_path = out_dir / "connection.json"
    yaml_path = out_dir / "connection.yaml"
    env_path = out_dir / "connection.env"

    json_text = json.dumps(manifest, indent=2, sort_keys=True)
    json_path.write_text(json_text + "\n")
    yaml_path.write_text(json_text + "\n")

    env_lines = []
    for key in sorted(env_map.keys()):
        env_lines.append(f"{key}={env_map[key]}")
    env_path.write_text("\n".join(env_lines) + "\n")

    manifest_path = out_dir / "manifest.sha256"
    files = [env_path, json_path, yaml_path]
    lines = []
    for path in sorted(files, key=lambda p: p.name):
        lines.append(f"{sha256_file(path)}  {path.name}")
    manifest_path.write_text("\n".join(lines) + "\n")

    print(f"PASS render: {binding_path} -> {out_dir}")
PY
