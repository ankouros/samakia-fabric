#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

POLICY_FILE="${FABRIC_REPO_ROOT}/fabric-core/ha/placement-policy.yml"

usage() {
  cat >&2 <<'EOT'
Usage:
  enforce-placement.sh [--env <env>] [--all] [--policy <path>] [--inventory-json <path>]

Runs placement enforcement (read-only). Enforcement uses terraform output by default
to avoid ansible-inventory IP discovery. Violations fail unless HA_OVERRIDE=1 and
HA_OVERRIDE_REASON is provided (override path is explicit and logged).
EOT
}

mode="all"
explicit_env=""
inventory_json=""
policy_path="${POLICY_FILE}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      explicit_env="${2:-}"
      mode="env"
      shift 2
      ;;
    --all)
      mode="all"
      shift
      ;;
    --policy)
      policy_path="${2:-}"
      shift 2
      ;;
    --inventory-json)
      inventory_json="${2:-}"
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

if [[ "${mode}" == "env" && -z "${explicit_env}" ]]; then
  echo "ERROR: --env requires a value" >&2
  exit 2
fi

if [[ -n "${inventory_json}" && "${mode}" != "env" ]]; then
  echo "ERROR: --inventory-json requires --env (single environment only)" >&2
  exit 2
fi

env_args=(--all)
if [[ "${mode}" == "env" ]]; then
  env_args=(--env "${explicit_env}")
fi

extra_args=()
if [[ -n "${inventory_json}" ]]; then
  extra_args+=(--inventory-json "${inventory_json}")
else
  extra_args+=(--inventory-source "tf-output")
fi

bash "${FABRIC_REPO_ROOT}/ops/scripts/ha/placement-validate.sh" \
  --enforce \
  --policy "${policy_path}" \
  "${env_args[@]}" \
  "${extra_args[@]}"
