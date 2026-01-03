#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


bindings_root="${FABRIC_REPO_ROOT}/contracts/bindings/tenants"
if [[ ! -d "${bindings_root}" ]]; then
  echo "ERROR: bindings root not found: ${bindings_root}" >&2
  exit 1
fi

mapfile -t bindings < <(find "${bindings_root}" -type f -name "*.binding.yml" -print | sort)
if [[ ${#bindings[@]} -eq 0 ]]; then
  echo "ERROR: no binding contracts found under ${bindings_root}" >&2
  exit 1
fi

"${FABRIC_REPO_ROOT}/ops/bindings/validate/validate-binding-schema.sh"
"${FABRIC_REPO_ROOT}/ops/bindings/validate/validate-binding-semantics.sh"

BINDINGS_LIST="$(printf '%s\n' "${bindings[@]}")" python3 - <<'PY'
import os
import sys
from pathlib import Path
import yaml

bindings = [Path(p) for p in os.environ.get("BINDINGS_LIST", "").splitlines() if p]

records = []
errors = []

def load_yaml(path: Path):
    try:
        return yaml.safe_load(path.read_text())
    except yaml.YAMLError as exc:
        errors.append(f"{path}: invalid YAML ({exc})")
        return None

for binding in bindings:
    data = load_yaml(binding)
    if not data:
        continue
    meta = data.get("metadata", {})
    tenant = meta.get("tenant")
    env = meta.get("env")
    if not tenant:
        errors.append(f"{binding}: metadata.tenant missing")
        continue
    if not env:
        errors.append(f"{binding}: metadata.env missing")
        continue
    records.append((tenant, env, str(binding)))

if errors:
    for err in errors:
        print(f"FAIL safety: {err}")
    sys.exit(1)

for tenant, env, path in records:
    print(f"{tenant}\t{env}\t{path}")
PY

prod_found=0
declare -A seen_tenants

while IFS=$'\t' read -r tenant env binding_path; do
  if [[ -z "${tenant}" || -z "${env}" ]]; then
    continue
  fi
  seen_tenants["${tenant}"]=1
  if [[ "${env}" == "prod" ]]; then
    prod_found=1
  fi
  if [[ "${env}" != "prod" && "${env}" != "staging" && "${env}" != "shared" && "${env}" != "dev" ]]; then
    echo "FAIL safety: ${binding_path}: env '${env}' is not allowed" >&2
    exit 1
  fi
  echo "PASS safety: ${binding_path}: env '${env}'"
done <<< "$(BINDINGS_LIST="$(printf '%s\n' "${bindings[@]}")" python3 - <<'PY'
import os
import sys
from pathlib import Path
import yaml

bindings = [Path(p) for p in os.environ.get("BINDINGS_LIST", "").splitlines() if p]

for binding in bindings:
    data = yaml.safe_load(binding.read_text())
    meta = data.get("metadata", {})
    tenant = meta.get("tenant") or ""
    env = meta.get("env") or ""
    print(f"{tenant}\t{env}\t{binding}")
PY
)"

if [[ "${prod_found}" -eq 1 && "${BIND_PROD_APPROVED:-}" != "1" ]]; then
  echo "FAIL safety: prod binding detected; set BIND_PROD_APPROVED=1 to acknowledge" >&2
  exit 1
fi

for tenant in "${!seen_tenants[@]}"; do
  tenant_root="${FABRIC_REPO_ROOT}/contracts/tenants/${tenant}"
  examples_root="${FABRIC_REPO_ROOT}/contracts/tenants/examples/${tenant}"
  if [[ -f "${tenant_root}/capacity.yml" ]]; then
    capacity_root="${FABRIC_REPO_ROOT}/contracts/tenants"
  elif [[ -f "${examples_root}/capacity.yml" ]]; then
    capacity_root="${FABRIC_REPO_ROOT}/contracts/tenants/examples"
  else
    echo "FAIL safety: capacity.yml not found for tenant ${tenant}" >&2
    exit 1
  fi

  echo "PASS safety: capacity guard for tenant ${tenant}"
  TENANTS_ROOT="${capacity_root}" TENANT="${tenant}" \
    bash "${FABRIC_REPO_ROOT}/ops/substrate/capacity/capacity-guard.sh"
done

if [[ "${prod_found}" -eq 1 ]]; then
  echo "PASS safety: prod bindings approved with BIND_PROD_APPROVED=1"
fi
