#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

policy_file="${POLICY_FILE:-${FABRIC_REPO_ROOT}/contracts/observability/policy.yml}"
schema_file="${SCHEMA_FILE:-${FABRIC_REPO_ROOT}/contracts/observability/policy.schema.json}"

if [[ ! -f "${policy_file}" ]]; then
  echo "ERROR: observability policy file not found: ${policy_file}" >&2
  exit 1
fi

if [[ ! -f "${schema_file}" ]]; then
  echo "ERROR: observability policy schema not found: ${schema_file}" >&2
  exit 1
fi

python3 - "${policy_file}" "${schema_file}" <<'PY'
import json
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for policy validation: {exc}")

policy_path = sys.argv[1]
schema_path = sys.argv[2]

with open(schema_path, "r", encoding="utf-8") as fh:
    schema = json.load(fh)

with open(policy_path, "r", encoding="utf-8") as fh:
    policy = yaml.safe_load(fh) or {}

errors = []

if not isinstance(policy, dict):
    errors.append("policy must be a mapping")

version = policy.get("version")
if not isinstance(version, int) or version < 1:
    errors.append("version must be an integer >= 1")

shared = policy.get("shared_observability")
if not isinstance(shared, dict):
    errors.append("shared_observability must be a mapping")
else:
    replicas_min = shared.get("replicas_min")
    if not isinstance(replicas_min, int) or replicas_min < 2:
        errors.append("shared_observability.replicas_min must be an integer >= 2")

    anti_affinity = shared.get("anti_affinity_required")
    if anti_affinity is not True:
        errors.append("shared_observability.anti_affinity_required must be true")

    min_hosts = shared.get("min_hosts")
    if not isinstance(min_hosts, int) or min_hosts < 2:
        errors.append("shared_observability.min_hosts must be an integer >= 2")

    scope = shared.get("scope")
    if not isinstance(scope, list) or not scope or not all(isinstance(x, str) and x.strip() for x in scope):
        errors.append("shared_observability.scope must be a non-empty list of strings")
    else:
        required_scope = {"prometheus", "alertmanager", "grafana", "loki"}
        missing = sorted(required_scope - {x.strip() for x in scope})
        if missing:
            errors.append(f"shared_observability.scope missing required entries: {', '.join(missing)}")

    if isinstance(replicas_min, int) and isinstance(min_hosts, int) and min_hosts > replicas_min:
        errors.append("shared_observability.min_hosts cannot exceed replicas_min")

if errors:
    for err in errors:
        print(f"ERROR: {err}", file=sys.stderr)
    raise SystemExit(1)

print("PASS: observability policy validated")
PY
