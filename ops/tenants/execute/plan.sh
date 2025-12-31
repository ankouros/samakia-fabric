#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  plan.sh --tenant <id> [--env <env>]

Notes:
  - Read-only plan; validates contracts and execute policy.
EOT
}

tenant=""
env_name="${ENV:-}"

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

if [[ -z "${tenant}" ]]; then
  echo "ERROR: --tenant is required" >&2
  usage
  exit 2
fi

if [[ -z "${env_name}" ]]; then
  echo "ERROR: ENV is required" >&2
  exit 2
fi

"${FABRIC_REPO_ROOT}/ops/tenants/execute/validate-execute-policy.sh"
"${FABRIC_REPO_ROOT}/ops/tenants/validate.sh"
"${FABRIC_REPO_ROOT}/ops/tenants/validate-policies.sh"
"${FABRIC_REPO_ROOT}/ops/tenants/validate-consumer-bindings.sh"

policy_file="${FABRIC_REPO_ROOT}/ops/tenants/execute/execute-policy.yml"
contracts_root="${FABRIC_REPO_ROOT}/contracts/tenants/examples"

tenant_dir="${contracts_root}/${tenant}"
if [[ ! -d "${tenant_dir}" ]]; then
  echo "ERROR: tenant not found: ${tenant_dir}" >&2
  exit 1
fi

if [[ -n "${EXECUTE_REASON:-}" ]]; then
  reason_ok=1
else
  reason_ok=0
fi

ENV_NAME="${env_name}" TENANT_DIR="${tenant_dir}" POLICY_FILE="${policy_file}" REASON_OK="${reason_ok}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

env_name = os.environ["ENV_NAME"]
tenant_dir = Path(os.environ["TENANT_DIR"])
policy_path = Path(os.environ["POLICY_FILE"])
reason_ok = os.environ["REASON_OK"] == "1"

policy = json.loads(policy_path.read_text())
allowed_envs = policy.get("allowed_envs", [])
allowed_tenants = policy.get("allowed_tenants", [])
allowed_consumers = set(policy.get("allowed_consumers", []))
require_reason = policy.get("require_reason", True)

errors = []
if env_name not in allowed_envs:
    errors.append(f"env '{env_name}' not allowlisted for execute")

if tenant_dir.name not in allowed_tenants:
    errors.append(f"tenant '{tenant_dir.name}' not allowlisted for execute")

if require_reason and not reason_ok:
    errors.append("EXECUTE_REASON is required by policy")

if errors:
    for err in errors:
        print(f"FAIL plan: {err}")
    sys.exit(1)

bindings = []
for enabled in tenant_dir.rglob("consumers/**/enabled.yml"):
    data = json.loads(enabled.read_text())
    spec = data.get("spec", {})
    consumer = spec.get("consumer")
    mode = spec.get("mode")
    if consumer not in allowed_consumers:
        print(f"FAIL plan: consumer '{consumer}' not allowlisted", file=sys.stderr)
        sys.exit(1)
    bindings.append({
        "path": str(enabled),
        "consumer": consumer,
        "mode": mode,
        "endpoint_ref": spec.get("endpoint_ref"),
        "secret_ref": spec.get("secret_ref"),
    })

if not bindings:
    print("FAIL plan: no enabled bindings found")
    sys.exit(1)

print("PLAN: tenant execute preview")
print(f"- tenant: {tenant_dir.name}")
print(f"- env: {env_name}")
print(f"- bindings: {len(bindings)}")
for bind in bindings:
    print(f"  - {bind['consumer']} mode={bind['mode']} endpoint={bind['endpoint_ref']} secret_ref={bind['secret_ref']}")
PY

if [[ "${env_name}" == "samakia-prod" ]]; then
  if [[ "${MAINT_WINDOW_START:-}" == "" || "${MAINT_WINDOW_END:-}" == "" ]]; then
    echo "ERROR: MAINT_WINDOW_START/END required for prod" >&2
    exit 2
  fi
  "${FABRIC_REPO_ROOT}/ops/tenants/execute/change-window.sh"
fi

exit 0
