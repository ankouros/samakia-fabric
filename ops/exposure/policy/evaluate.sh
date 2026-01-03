#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  evaluate.sh --tenant <id> --workload <id> --env <env> --providers <csv> --variants <csv> [--out <path>]

Notes:
  - Produces a decision JSON (allow/deny + guards).
EOT
}

policy_file="${POLICY_FILE:-${FABRIC_REPO_ROOT}/contracts/exposure/exposure-policy.yml}"
tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"
providers="${PROVIDERS:-}"
variants="${VARIANTS:-}"
output="${DECISION_OUT:-}"

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
    --out)
      output="$2"
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

if [[ -z "${tenant}" || -z "${workload}" || -z "${env_name}" || -z "${providers}" || -z "${variants}" ]]; then
  echo "ERROR: tenant, workload, env, providers, variants are required" >&2
  usage
  exit 2
fi

if [[ ! -f "${policy_file}" ]]; then
  echo "ERROR: policy file not found: ${policy_file}" >&2
  exit 1
fi

TENANT="${tenant}" WORKLOAD="${workload}" ENV_NAME="${env_name}" \
PROVIDERS="${providers}" VARIANTS="${variants}" POLICY_FILE="${policy_file}" OUTPUT_PATH="${output}" \
EXPOSURE_SIGN="${EXPOSURE_SIGN:-0}" CHANGE_WINDOW_START="${CHANGE_WINDOW_START:-}" CHANGE_WINDOW_END="${CHANGE_WINDOW_END:-}" \
python3 - <<'PY'
import json
import os
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: PyYAML required for policy evaluation: {exc}")

policy_path = os.environ["POLICY_FILE"]
output_path = os.environ.get("OUTPUT_PATH", "")

with open(policy_path, "r", encoding="utf-8") as handle:
    policy = yaml.safe_load(handle)

spec = policy.get("spec", {})
metadata = policy.get("metadata", {})
allowlist = spec.get("allowlist", {})

env_name = os.environ["ENV_NAME"]
tenant = os.environ["TENANT"]
workload = os.environ["WORKLOAD"]

providers = [p for p in os.environ["PROVIDERS"].split(",") if p]
variants = [v for v in os.environ["VARIANTS"].split(",") if v]

reason_codes = []
required_guards = []

allowed_envs = allowlist.get("envs", [])
if env_name not in allowed_envs:
    reason_codes.append("env_not_allowlisted")

allowed_tenants = allowlist.get("tenants", {}).get(env_name, [])
if tenant not in allowed_tenants:
    reason_codes.append("tenant_not_allowlisted")

allowed_workloads = allowlist.get("workloads", {}).get(tenant, [])
if workload not in allowed_workloads:
    reason_codes.append("workload_not_allowlisted")

allowed_providers = set(allowlist.get("providers", []))
for provider in providers:
    if provider not in allowed_providers:
        reason_codes.append("provider_not_allowlisted")
        break

allowed_variants = set(allowlist.get("variants", []))
for variant in variants:
    if variant not in allowed_variants:
        reason_codes.append("variant_not_allowlisted")
        break

invariants = spec.get("invariants", {})
if invariants.get("tls_required") is not True:
    reason_codes.append("policy_tls_required_disabled")
if invariants.get("allow_plaintext_endpoints") is not False:
    reason_codes.append("policy_plaintext_allowed")

enforcement = spec.get("enforcement", {})
prod_rules = enforcement.get("prod", {})
non_prod_rules = enforcement.get("non_prod", {})

if env_name == "samakia-prod":
    if prod_rules.get("require_approval") is True:
        required_guards.append("approval")
    if prod_rules.get("require_signing") is True:
        required_guards.append("signing")
        if os.environ.get("EXPOSURE_SIGN", "0") != "1":
            reason_codes.append("prod_signing_required")
    if prod_rules.get("require_change_window") is True:
        required_guards.append("change_window")
        if not os.environ.get("CHANGE_WINDOW_START") or not os.environ.get("CHANGE_WINDOW_END"):
            reason_codes.append("prod_change_window_required")
else:
    if non_prod_rules.get("require_approval") is True:
        required_guards.append("approval")
    if non_prod_rules.get("require_signing") is True:
        required_guards.append("signing")
    if non_prod_rules.get("require_change_window") is True:
        required_guards.append("change_window")

allowed = len(reason_codes) == 0

payload = {
    "allowed": allowed,
    "reason_codes": sorted(set(reason_codes)),
    "required_guards": sorted(set(required_guards)),
    "policy_version": metadata.get("policy_version"),
}

output_text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
if output_path:
    with open(output_path, "w", encoding="utf-8") as handle:
        handle.write(output_text)
else:
    sys.stdout.write(output_text)
PY
