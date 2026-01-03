#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


TENANT="${TENANT:-}"
if [[ -z "${TENANT}" ]]; then
  echo "ERROR: TENANT is required" >&2
  exit 2
fi

output=""
status="UNKNOWN"
violations=()

if [[ ! -f "${FABRIC_REPO_ROOT}/contracts/tenants/examples/${TENANT}/capacity.yml" && ! -f "${FABRIC_REPO_ROOT}/contracts/tenants/${TENANT}/capacity.yml" ]]; then
  python3 - "${TENANT}" <<'PY'
import json
import sys
print(json.dumps({"tenant": sys.argv[1], "status": "UNKNOWN", "issues": ["capacity.yml missing"]}, indent=2, sort_keys=True))
PY
  exit 0
fi

set +e
output=$(TENANT="${TENANT}" CAPACITY_EVIDENCE_ROOT="" bash "${FABRIC_REPO_ROOT}/ops/substrate/capacity/capacity-guard.sh" 2>&1)
exit_code=$?
set -e

if [[ ${exit_code} -eq 2 ]]; then
  status="FAIL"
elif echo "${output}" | rg -q "^WARN"; then
  status="WARN"
else
  status="PASS"
fi

while IFS= read -r line; do
  if [[ "${line}" == -* ]]; then
    violations+=("${line#- }")
  fi
done <<<"${output}"

python3 - "${TENANT}" "${status}" "${output}" <<'PY'
import json
import sys

tenant = sys.argv[1]
status = sys.argv[2]
raw = sys.argv[3]
issues = [line[2:] for line in raw.splitlines() if line.startswith("- ")]
print(json.dumps({"tenant": tenant, "status": status, "issues": issues}, indent=2, sort_keys=True))
PY
