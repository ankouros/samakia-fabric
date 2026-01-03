#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  apply.sh --tenant <id> [--env <env>]

Guards (required):
  TENANT_EXECUTE=1
  I_UNDERSTAND_TENANT_MUTATION=1
  EXECUTE_REASON="<text>"
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

if [[ "${TENANT_EXECUTE:-0}" != "1" ]]; then
  echo "ERROR: TENANT_EXECUTE=1 is required for apply" >&2
  exit 2
fi

if [[ "${I_UNDERSTAND_TENANT_MUTATION:-0}" != "1" ]]; then
  echo "ERROR: I_UNDERSTAND_TENANT_MUTATION=1 is required" >&2
  exit 2
fi

if [[ -z "${EXECUTE_REASON:-}" ]]; then
  echo "ERROR: EXECUTE_REASON is required" >&2
  exit 2
fi

policy_file="${FABRIC_REPO_ROOT}/ops/tenants/execute/execute-policy.yml"
contracts_root="${FABRIC_REPO_ROOT}/contracts/tenants/examples"
tenant_dir="${contracts_root}/${tenant}"
if [[ ! -d "${tenant_dir}" ]]; then
  echo "ERROR: tenant not found: ${tenant_dir}" >&2
  exit 1
fi

"${FABRIC_REPO_ROOT}/ops/tenants/execute/validate-execute-policy.sh"
"${FABRIC_REPO_ROOT}/ops/tenants/validate.sh"
"${FABRIC_REPO_ROOT}/ops/tenants/validate-policies.sh"
"${FABRIC_REPO_ROOT}/ops/tenants/validate-consumer-bindings.sh"

ENV="${env_name}" EXECUTE_REASON="${EXECUTE_REASON}" bash "${FABRIC_REPO_ROOT}/ops/tenants/execute/plan.sh" --tenant "${tenant}" --env "${env_name}"

if [[ "${env_name}" == "samakia-prod" ]]; then
  "${FABRIC_REPO_ROOT}/ops/tenants/execute/change-window.sh"
fi

policy_json=$(cat "${policy_file}")
require_signing_for_prod=$(python3 - <<PY
import json
policy = json.loads('''${policy_json}''')
print("1" if policy.get("require_signing_for_prod", True) else "0")
PY
)

if [[ "${env_name}" == "samakia-prod" && "${require_signing_for_prod}" == "1" ]]; then
  if [[ "${EVIDENCE_SIGN:-0}" != "1" || -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
    echo "ERROR: prod execute requires EVIDENCE_SIGN=1 and EVIDENCE_SIGN_KEY" >&2
    exit 2
  fi
fi

if [[ -n "${EVIDENCE_SIGN_KEY:-}" && "${EVIDENCE_SIGN:-0}" != "1" ]]; then
  echo "ERROR: EVIDENCE_SIGN_KEY is set; set EVIDENCE_SIGN=1 to sign execute evidence" >&2
  exit 2
fi

bindings_tmp="$(mktemp)"
trap 'rm -f "${bindings_tmp}"' EXIT

python3 - <<PY >"${bindings_tmp}"
import json
from pathlib import Path

tenant_dir = Path("${tenant_dir}")

for enabled in tenant_dir.rglob("consumers/**/enabled.yml"):
    data = json.loads(enabled.read_text())
    spec = data.get("spec", {})
    consumer = spec.get("consumer")
    mode = spec.get("mode")
    endpoint_ref = spec.get("endpoint_ref")
    secret_ref = spec.get("secret_ref")
    print(f"{consumer}|{mode}|{endpoint_ref}|{secret_ref}")
PY

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
evidence_root="${FABRIC_REPO_ROOT}/evidence/tenants/${tenant}/${stamp}/execute"
mkdir -p "${evidence_root}"

cat >"${evidence_root}/report.md" <<EOF_REPORT
# Tenant Execute Apply

Tenant: ${tenant}
Environment: ${env_name}
Timestamp (UTC): ${stamp}
Reason: ${EXECUTE_REASON}

Notes:
- Only bindings with mode=execute will issue credentials.
- Substrate provisioning is not implemented in Phase 10 Part 2.
EOF_REPORT

python3 - <<PY
import json
from pathlib import Path

metadata = {
    "tenant": "${tenant}",
    "environment": "${env_name}",
    "timestamp_utc": "${stamp}",
    "reason": "${EXECUTE_REASON}",
    "policy_file": "ops/tenants/execute/execute-policy.yml"
}
Path("${evidence_root}/metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
PY

while IFS='|' read -r consumer mode endpoint_ref secret_ref; do
  if [[ -z "${consumer}" ]]; then
    continue
  fi
  if [[ "${mode}" == "execute" ]]; then
    TENANT_CREDS_ISSUE=1 \
      bash "${FABRIC_REPO_ROOT}/ops/tenants/creds/issue.sh" \
        --tenant "${tenant}" --consumer "${consumer}" --endpoint "${endpoint_ref}"
    echo "PASS apply: issued credentials for ${consumer}" >>"${evidence_root}/report.md"
  else
    echo "SKIP apply: ${consumer} mode=${mode}" >>"${evidence_root}/report.md"
  fi
  if [[ "${TENANT_SUBSTRATE_READY:-0}" != "1" ]]; then
    echo "NOTE: substrate creation skipped for ${consumer} (TENANT_SUBSTRATE_READY not set)" >>"${evidence_root}/report.md"
  fi
  echo "binding ${consumer} endpoint_ref=${endpoint_ref} secret_ref=${secret_ref}" >>"${evidence_root}/report.md"
  echo "---" >>"${evidence_root}/report.md"
done <"${bindings_tmp}"

( cd "${evidence_root}" && find . -type f ! -name "manifest.sha256" -print0 | sort -z | xargs -0 sha256sum > manifest.sha256 )

bash "${FABRIC_REPO_ROOT}/ops/tenants/execute/signer.sh" "${evidence_root}/manifest.sha256"

echo "PASS execute apply: evidence at ${evidence_root}"
