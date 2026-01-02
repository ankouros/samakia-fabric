#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  echo "usage: render.sh --binding <connection.json> --out <plan.json> --tenant <id> --workload <id> --env <env>" >&2
}

binding_path=""
output_path=""
tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"
policy_file="${POLICY_FILE:-${FABRIC_REPO_ROOT}/contracts/exposure/exposure-policy.yml}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binding)
      binding_path="$2"
      shift 2
      ;;
    --out)
      output_path="$2"
      shift 2
      ;;
    --tenant)
      tenant="$2"
      shift 2
      ;;
    --workload)
      workload="$2"
      shift 2
      ;;
    --env)
      env_name="$2"
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

if [[ -z "${binding_path}" || -z "${output_path}" || -z "${tenant}" || -z "${workload}" || -z "${env_name}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${binding_path}" ]]; then
  echo "ERROR: binding manifest not found: ${binding_path}" >&2
  exit 1
fi

if [[ ! -f "${policy_file}" ]]; then
  echo "ERROR: policy file not found: ${policy_file}" >&2
  exit 1
fi

BINDING_PATH="${binding_path}" OUTPUT_PATH="${output_path}" TENANT="${tenant}" WORKLOAD="${workload}" ENV_NAME="${env_name}" POLICY_FILE="${policy_file}" \
EXPOSURE_BUILD_ID="${EXPOSURE_BUILD_ID:-}" EXPOSURE_STAMP="${EXPOSURE_STAMP:-}" \
python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: PyYAML required: {exc}")

binding_path = Path(os.environ["BINDING_PATH"])
output_path = Path(os.environ["OUTPUT_PATH"])
policy_path = Path(os.environ["POLICY_FILE"])

tenant = os.environ["TENANT"]
workload = os.environ["WORKLOAD"]
env_name = os.environ["ENV_NAME"]

policy = yaml.safe_load(policy_path.read_text())
policy_version = policy.get("metadata", {}).get("policy_version")
naming = policy.get("spec", {}).get("naming", {})
output_format = naming.get("output_format", "YYYYMMDDTHHMMSSZ-<build_id>")
build_id_source = naming.get("build_id_source", "env:EXPOSURE_BUILD_ID")

build_id = "local"
if build_id_source.startswith("env:"):
    env_key = build_id_source.split(":", 1)[1]
    build_id = os.environ.get(env_key, "local") or "local"

stamp = os.environ.get("EXPOSURE_STAMP")
if not stamp:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

stamp_id = f"{stamp}-{build_id}"

payload = json.loads(binding_path.read_text())
consumers = payload.get("consumers", [])

if not consumers:
    raise SystemExit("ERROR: no consumers in binding manifest")

artifact_base = f"artifacts/exposure/{env_name}/{tenant}/{workload}"

artifacts = []
providers = []
variants = []

for consumer in consumers:
    provider = consumer.get("provider")
    variant = consumer.get("variant")
    if provider and provider not in providers:
        providers.append(provider)
    if variant and variant not in variants:
        variants.append(variant)

    tags = {}
    for key in naming.get("tag_keys", []):
        if key == "tenant":
            tags[key] = tenant
        elif key == "workload":
            tags[key] = workload
        elif key == "provider":
            tags[key] = provider
        elif key == "variant":
            tags[key] = variant
        elif key == "policy_version":
            tags[key] = policy_version

    artifacts.append(
        {
            "path": f"{artifact_base}/{provider}/{variant}/{stamp_id}",
            "type": "exposure-bundle",
            "naming": {
                "format": output_format,
                "value": stamp_id,
                "build_id": build_id,
                "stamp": stamp,
            },
            "tags": tags,
        }
    )

plan = {
    "tenant": tenant,
    "workload": workload,
    "env": env_name,
    "policy_version": policy_version,
    "build_id": build_id,
    "stamp": stamp,
    "providers": sorted(providers),
    "variants": sorted(variants),
    "artifacts": sorted(artifacts, key=lambda item: (item.get("path") or "")),
}

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
PY
