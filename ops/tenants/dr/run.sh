#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  run.sh --tenant <id> [--mode dry-run|execute] [--env <env>]

Guards (execute mode only):
  DR_EXECUTE=1
  TENANT_EXECUTE=1
  I_UNDERSTAND_TENANT_MUTATION=1
  EXECUTE_REASON="<text>"
EOT
}

tenant=""
mode="dry-run"
env_name="${ENV:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)
      tenant="${2:-}"
      shift 2
      ;;
    --mode)
      mode="${2:-}"
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

if [[ "${mode}" != "dry-run" && "${mode}" != "execute" ]]; then
  echo "ERROR: mode must be dry-run or execute" >&2
  exit 2
fi

"${FABRIC_REPO_ROOT}/ops/tenants/dr/validate-dr.sh"

if [[ "${mode}" == "execute" ]]; then
  if [[ "${DR_EXECUTE:-0}" != "1" ]]; then
    echo "ERROR: DR_EXECUTE=1 required for execute mode" >&2
    exit 2
  fi
  if [[ "${TENANT_EXECUTE:-0}" != "1" || "${I_UNDERSTAND_TENANT_MUTATION:-0}" != "1" ]]; then
    echo "ERROR: TENANT_EXECUTE=1 and I_UNDERSTAND_TENANT_MUTATION=1 required" >&2
    exit 2
  fi
  if [[ -z "${EXECUTE_REASON:-}" ]]; then
    echo "ERROR: EXECUTE_REASON is required" >&2
    exit 2
  fi
  "${FABRIC_REPO_ROOT}/ops/tenants/execute/validate-execute-policy.sh"
  POLICY_FILE="${FABRIC_REPO_ROOT}/ops/tenants/execute/execute-policy.yml" \
    ENV_NAME="${env_name}" TENANT_NAME="${tenant}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

policy = json.loads(Path(os.environ["POLICY_FILE"]).read_text())
env_name = os.environ["ENV_NAME"]
tenant_name = os.environ["TENANT_NAME"]

allowed_envs = policy.get("allowed_envs", [])
allowed_tenants = policy.get("allowed_tenants", [])
require_reason = policy.get("require_reason", True)

errors = []
if env_name not in allowed_envs:
    errors.append(f"env '{env_name}' not allowlisted for execute")
if tenant_name not in allowed_tenants:
    errors.append(f"tenant '{tenant_name}' not allowlisted for execute")
if require_reason and not os.environ.get("EXECUTE_REASON"):
    errors.append("EXECUTE_REASON is required by policy")

if errors:
    for err in errors:
        print(f"FAIL dr execute: {err}", file=sys.stderr)
    sys.exit(1)
PY
  if [[ "${env_name}" == "samakia-prod" ]]; then
    "${FABRIC_REPO_ROOT}/ops/tenants/execute/change-window.sh"
  fi
fi

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
contracts_root="${FABRIC_REPO_ROOT}/contracts/tenants/examples"
tenant_dir="${contracts_root}/${tenant}"
if [[ ! -d "${tenant_dir}" ]]; then
  echo "ERROR: tenant not found: ${tenant_dir}" >&2
  exit 1
fi

evidence_root="${FABRIC_REPO_ROOT}/evidence/tenants/${tenant}/${stamp}/dr"
mkdir -p "${evidence_root}"

cat >"${evidence_root}/report.md" <<EOF_REPORT
# Tenant DR Run

Tenant: ${tenant}
Environment: ${env_name}
Mode: ${mode}
Timestamp (UTC): ${stamp}
Reason: ${EXECUTE_REASON:-not-required}

Notes:
- This harness records DR readiness only.
- No substrate mutations are performed in dry-run mode.
EOF_REPORT

python3 - <<PY
import json
from pathlib import Path

data = {
    "tenant": "${tenant}",
    "environment": "${env_name}",
    "mode": "${mode}",
    "timestamp_utc": "${stamp}",
    "reason": "${EXECUTE_REASON:-}"
}
Path("${evidence_root}/metadata.json").write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

python3 - <<PY
import json
from pathlib import Path

tenant_dir = Path("${tenant_dir}")
entries = []
for enabled in tenant_dir.rglob("consumers/**/enabled.yml"):
    data = json.loads(enabled.read_text())
    spec = data.get("spec", {})
    entries.append({
        "consumer": spec.get("consumer"),
        "dr_testcases": spec.get("dr_testcases", []),
        "restore_testcases": spec.get("restore_testcases", []),
    })
Path("${evidence_root}/testcases.json").write_text(json.dumps(entries, indent=2, sort_keys=True) + "\n")
PY

( cd "${evidence_root}" && find . -type f ! -name "manifest.sha256" -print0 | sort -z | xargs -0 sha256sum > manifest.sha256 )

if [[ "${mode}" == "execute" ]]; then
  echo "PASS dr execute (placeholder): ${tenant}" >>"${evidence_root}/report.md"
else
  echo "PASS dr dry-run: ${tenant}" >>"${evidence_root}/report.md"
fi

echo "PASS dr: ${evidence_root}"
