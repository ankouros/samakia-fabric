#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

binding_arg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --binding)
      binding_arg="$2"
      shift 2
      ;;
    *)
      echo "usage: bind.sh [--binding <path>]" >&2
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

"${FABRIC_REPO_ROOT}/ops/bindings/validate/validate-binding-schema.sh"
"${FABRIC_REPO_ROOT}/ops/bindings/validate/validate-binding-semantics.sh"
"${FABRIC_REPO_ROOT}/ops/bindings/validate/validate-binding-safety.sh"

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

for binding in "${bindings[@]}"; do
  if [[ ! -f "${binding}" ]]; then
    echo "ERROR: binding not found: ${binding}" >&2
    exit 1
  fi

  read -r tenant env workload_id < <(python3 - <<PY
import json
from pathlib import Path

binding = Path("${binding}")
data = json.loads(binding.read_text())
meta = data.get("metadata", {})
tenant = meta.get("tenant", "")
env = meta.get("env", "")
workload_id = meta.get("workload_id", "")
print(f"{tenant} {env} {workload_id}")
PY
)

  if [[ -z "${tenant}" || -z "${env}" || -z "${workload_id}" ]]; then
    echo "ERROR: binding metadata missing in ${binding}" >&2
    exit 1
  fi

  if [[ "${BIND_EXECUTE:-0}" != "1" ]]; then
    echo "DRY_RUN: binding apply for ${tenant}/${workload_id} (set BIND_EXECUTE=1 to apply)"
  else
    if [[ "${env}" == "prod" ]]; then
      if [[ "${BIND_PROD_APPROVED:-}" != "1" ]]; then
        echo "ERROR: prod binding requires BIND_PROD_APPROVED=1" >&2
        exit 1
      fi
      if [[ "${EVIDENCE_SIGN:-0}" != "1" || -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
        echo "ERROR: prod binding apply requires EVIDENCE_SIGN=1 and EVIDENCE_SIGN_KEY" >&2
        exit 1
      fi
      bash "${FABRIC_REPO_ROOT}/ops/tenants/execute/change-window.sh"
    fi
  fi

  out_dir="${FABRIC_REPO_ROOT}/artifacts/bindings/${tenant}/${workload_id}"
  out_root="${FABRIC_REPO_ROOT}/artifacts/bindings"
  export OUT_ROOT="${out_root}"
  export FABRIC_REPO_ROOT
  bash "${FABRIC_REPO_ROOT}/ops/bindings/render/render-connection-manifest.sh" --binding "${binding}"

  evidence_dir="${FABRIC_REPO_ROOT}/evidence/bindings/${tenant}/${stamp}"
  manifests_dir="${evidence_dir}/rendered-manifests"
  mkdir -p "${manifests_dir}"

  python3 - <<PY
import json
from pathlib import Path
binding = Path("${binding}")
output = Path("${evidence_dir}") / "binding.yml.redacted"

data = json.loads(binding.read_text())
for consumer in data.get("spec", {}).get("consumers", []):
    if "secret_ref" in consumer:
        consumer["secret_ref"] = "<redacted>"
output.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

  if [[ -d "${out_dir}" ]]; then
    cp "${out_dir}"/* "${manifests_dir}"/
  fi

  decision_json="${evidence_dir}/decision.json"
  policy_json="${evidence_dir}/policy.json"

  python3 - <<PY
import json
from pathlib import Path

Path("${evidence_dir}").mkdir(parents=True, exist_ok=True)

decision = {
    "tenant": "${tenant}",
    "workload_id": "${workload_id}",
    "env": "${env}",
    "mode": "execute" if "${BIND_EXECUTE:-0}" == "1" else "dry-run",
}
policy = {
    "bind_execute": "${BIND_EXECUTE:-0}",
    "bind_prod_approved": "${BIND_PROD_APPROVED:-}",
    "change_window_start": "${MAINT_WINDOW_START:-}",
    "change_window_end": "${MAINT_WINDOW_END:-}",
    "evidence_sign": "${EVIDENCE_SIGN:-0}",
}
Path("${decision_json}").write_text(json.dumps(decision, indent=2, sort_keys=True) + "\n")
Path("${policy_json}").write_text(json.dumps(policy, indent=2, sort_keys=True) + "\n")
PY

  manifest_file="${evidence_dir}/manifest.sha256"
  (
    cd "${evidence_dir}"
    find . -type f ! -name "manifest.sha256" ! -name "manifest.sha256.asc" | sort | while read -r file; do
      sha256sum "${evidence_dir}/${file#./}" | sed "s#${evidence_dir}/##"
    done
  ) > "${manifest_file}"

  if [[ "${env}" == "prod" && "${BIND_EXECUTE:-0}" == "1" ]]; then
    EVIDENCE_SIGN=1 EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
      bash "${FABRIC_REPO_ROOT}/ops/tenants/execute/signer.sh" "${manifest_file}"
  elif [[ "${EVIDENCE_SIGN:-0}" == "1" ]]; then
    bash "${FABRIC_REPO_ROOT}/ops/tenants/execute/signer.sh" "${manifest_file}"
  fi

  echo "PASS apply: ${tenant}/${workload_id} evidence -> ${evidence_dir}"

done
