#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


slo_path="${SLO_PATH:-}"

if [[ -z "${slo_path}" ]]; then
  if [[ -z "${TENANT:-}" || -z "${WORKLOAD:-}" ]]; then
    echo "ERROR: SLO_PATH or TENANT+WORKLOAD required" >&2
    exit 1
  fi
  root_primary="${SLO_ROOT:-${FABRIC_REPO_ROOT}/contracts/tenants/${TENANT}/slo}"
  root_examples="${SLO_EXAMPLES_ROOT:-${FABRIC_REPO_ROOT}/contracts/tenants/examples/${TENANT}/slo}"
  if [[ -f "${root_primary}/${WORKLOAD}.yml" ]]; then
    slo_path="${root_primary}/${WORKLOAD}.yml"
  elif [[ -f "${root_examples}/${WORKLOAD}.yml" ]]; then
    slo_path="${root_examples}/${WORKLOAD}.yml"
  fi
fi

if [[ -z "${slo_path}" || ! -f "${slo_path}" ]]; then
  echo "ERROR: SLO contract not found for tenant=${TENANT:-unknown} workload=${WORKLOAD:-unknown}" >&2
  exit 1
fi

if [[ -z "${OUT_PATH:-}" ]]; then
  python3 - "${slo_path}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
print(json.dumps(data, indent=2, sort_keys=True))
PY
  exit 0
fi

python3 - "${slo_path}" "${OUT_PATH}" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dest = Path(sys.argv[2])
data = json.loads(src.read_text())
dest.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
