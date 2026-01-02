#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  echo "usage: explain.sh --tenant <id> --workload <id> --env <env> [--binding <connection.json>] [--providers <csv> --variants <csv>]" >&2
}

tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"
providers="${PROVIDERS:-}"
variants="${VARIANTS:-}"
binding_path=""
policy_file="${POLICY_FILE:-${FABRIC_REPO_ROOT}/contracts/exposure/exposure-policy.yml}"

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --providers)
      providers="$2"
      shift 2
      ;;
    --variants)
      variants="$2"
      shift 2
      ;;
    --binding)
      binding_path="$2"
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

if [[ -z "${tenant}" || -z "${workload}" || -z "${env_name}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${policy_file}" ]]; then
  echo "ERROR: policy file not found: ${policy_file}" >&2
  exit 1
fi

if [[ -n "${binding_path}" ]]; then
  if [[ ! -f "${binding_path}" ]]; then
    echo "ERROR: binding manifest not found: ${binding_path}" >&2
    exit 1
  fi
  mapfile -t derived < <(BINDING_MANIFEST="${binding_path}" python3 - <<'PY'
import json
import os
from pathlib import Path

binding_path = Path(os.environ["BINDING_MANIFEST"])
payload = json.loads(binding_path.read_text())
consumers = payload.get("consumers", [])

providers = sorted({c.get("provider") for c in consumers if c.get("provider")})
variants = sorted({c.get("variant") for c in consumers if c.get("variant")})

print(",".join(providers))
print(",".join(variants))
PY
  )
  providers="${derived[0]:-}"
  variants="${derived[1]:-}"
fi

if [[ -z "${providers}" || -z "${variants}" ]]; then
  echo "ERROR: providers and variants are required (use --binding or --providers/--variants)" >&2
  exit 2
fi

decision_file="$(mktemp)"
TENANT="${tenant}" WORKLOAD="${workload}" ENV="${env_name}" PROVIDERS="${providers}" VARIANTS="${variants}" \
  DECISION_OUT="${decision_file}" POLICY_FILE="${policy_file}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/policy/evaluate.sh"

POLICY_FILE="${policy_file}" DECISION_FILE="${decision_file}" python3 - <<'PY'
import json
import os
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: PyYAML required: {exc}")

policy_path = os.environ["POLICY_FILE"]
decision_path = os.environ["DECISION_FILE"]

policy = yaml.safe_load(open(policy_path, "r", encoding="utf-8"))
meta = policy.get("metadata", {})

decision = json.loads(open(decision_path, "r", encoding="utf-8").read())

print("Exposure policy explanation")
print(f"- policy: {meta.get('name')} ({meta.get('policy_version')})")
print(f"- allowed: {decision.get('allowed')}")
if decision.get("reason_codes"):
    print("- reasons:")
    for reason in decision.get("reason_codes", []):
        print(f"  - {reason}")
if decision.get("required_guards"):
    print("- required guards:")
    for guard in decision.get("required_guards", []):
        print(f"  - {guard}")
PY

rm -f "${decision_file}"
