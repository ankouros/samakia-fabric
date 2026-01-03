#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  enforce-execute-policy.sh --tenant <id> --env <env> --consumer <consumer> --provider <provider> --variant <single|cluster> [--action apply|dr]
EOT
}

tenant=""
env_name=""
consumer=""
provider=""
variant=""
action="apply"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)
      tenant="${2:-}"
      shift 2
      ;;
    --env)
      env_name="${2:-}"
      shift 2
      ;;
    --consumer)
      consumer="${2:-}"
      shift 2
      ;;
    --provider)
      provider="${2:-}"
      shift 2
      ;;
    --variant)
      variant="${2:-}"
      shift 2
      ;;
    --action)
      action="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
 done

if [[ -z "${tenant}" || -z "${env_name}" || -z "${consumer}" || -z "${provider}" || -z "${variant}" ]]; then
  echo "ERROR: missing required arguments" >&2
  usage
  exit 2
fi

policy_file="${FABRIC_REPO_ROOT}/ops/substrate/common/execute-policy.yml"
if [[ ! -f "${policy_file}" ]]; then
  echo "ERROR: substrate execute policy missing: ${policy_file}" >&2
  exit 1
fi

TENANT="${tenant}" ENV_NAME="${env_name}" CONSUMER="${consumer}" PROVIDER="${provider}" VARIANT="${variant}" ACTION="${action}" POLICY_FILE="${policy_file}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

policy = json.loads(Path(os.environ["POLICY_FILE"]).read_text())

tenant = os.environ["TENANT"]
env_name = os.environ["ENV_NAME"]
consumer = os.environ["CONSUMER"]
provider = os.environ["PROVIDER"]
variant = os.environ["VARIANT"]
action = os.environ["ACTION"]

errors = []

if env_name not in policy.get("allowed_envs", []):
    errors.append(f"env not allowlisted: {env_name}")

if tenant not in policy.get("allowed_tenants", []):
    errors.append(f"tenant not allowlisted: {tenant}")

allowed_consumers = policy.get("allowed_consumers", [])
if consumer not in allowed_consumers:
    errors.append(f"consumer not allowlisted: {consumer}")

allowed_providers = policy.get("allowed_providers", {})
allowed_provider_list = allowed_providers.get(consumer, [])
if provider not in allowed_provider_list:
    errors.append(f"provider not allowlisted: {provider} for consumer {consumer}")

allowed_variants = policy.get("allowed_variants", [])
if variant not in allowed_variants:
    errors.append(f"variant not allowlisted: {variant}")

if action == "dr":
    if not policy.get("allow_dr_execute", False):
        errors.append("DR execute is not allowlisted by policy")

if errors:
    for err in errors:
        print(f"FAIL substrate execute policy: {err}", file=sys.stderr)
    sys.exit(2)

print("PASS substrate execute policy")
PY
