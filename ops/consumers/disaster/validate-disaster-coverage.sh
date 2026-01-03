#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


registry_path="${FABRIC_REPO_ROOT}/ops/consumers/disaster/disaster-testcases.yml"

if [[ ! -f "${registry_path}" ]]; then
  echo "ERROR: disaster testcases registry not found: ${registry_path}" >&2
  exit 1
fi

mapfile -t contracts < <(find "${FABRIC_REPO_ROOT}/contracts/consumers" -mindepth 2 -maxdepth 2 -name "*.yml" -print | sort)

REGISTRY_PATH="${registry_path}" CONTRACTS_LIST="$(printf '%s\n' "${contracts[@]}")" python3 - <<'PY'
import json
import sys
import os
from pathlib import Path

registry = json.loads(Path(os.environ["REGISTRY_PATH"]).read_text())
valid = set(registry.get("testcases", {}).keys())

errors = []

for contract_path in os.environ["CONTRACTS_LIST"].splitlines():
    contract = Path(contract_path)
    data = json.loads(contract.read_text())
    scenarios = data.get("spec", {}).get("disaster", {}).get("scenarios", [])
    prefix = contract.name
    if not scenarios:
        errors.append(f"{prefix}: no disaster scenarios declared")
        continue
    for scenario in scenarios:
        testcases = scenario.get("testcases", [])
        if not testcases:
            errors.append(f"{prefix}: scenario {scenario.get('name')} has no testcases")
            continue
        for testcase in testcases:
            if testcase not in valid:
                errors.append(f"{prefix}: testcase {testcase} not in registry")

if errors:
    for err in errors:
        print(f"FAIL disaster: {err}")
    sys.exit(1)

for contract_path in os.environ["CONTRACTS_LIST"].splitlines():
    print(f"PASS disaster: {contract_path}")
PY
