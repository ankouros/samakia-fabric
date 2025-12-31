#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

registry_path="${FABRIC_REPO_ROOT}/ops/consumers/disaster/disaster-testcases.yml"

if [[ ! -f "${registry_path}" ]]; then
  echo "ERROR: disaster testcases registry not found: ${registry_path}" >&2
  exit 1
fi

mapfile -t contracts < <(find "${FABRIC_REPO_ROOT}/contracts/consumers" -mindepth 2 -maxdepth 2 -name "*.yml" -print | sort)

if [[ ${#contracts[@]} -eq 0 ]]; then
  echo "ERROR: no consumer contracts found" >&2
  exit 1
fi

REGISTRY_PATH="${registry_path}" CONTRACTS_LIST="$(printf '%s\n' "${contracts[@]}")" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

registry = json.loads(Path(os.environ["REGISTRY_PATH"]).read_text())
contracts = [Path(p) for p in os.environ["CONTRACTS_LIST"].splitlines() if p]
repo_root = Path(os.environ["FABRIC_REPO_ROOT"]).resolve()

valid = registry.get("testcases", {})
errors = []

required_inputs = {
    "vip-failover": ["VIP_GROUP"],
    "service-restart": ["SERVICE", "TARGET"],
}

for contract_path in contracts:
    data = json.loads(contract_path.read_text())
    scenarios = data.get("spec", {}).get("disaster", {}).get("scenarios", [])
    prefix = contract_path.name

    if not scenarios:
        errors.append(f"{prefix}: no disaster scenarios declared")
        continue

    for scenario in scenarios:
        testcases = scenario.get("testcases", [])
        if not testcases:
            errors.append(f"{prefix}: scenario {scenario.get('name')} has no testcases")
            continue
        for testcase in testcases:
            entry = valid.get(testcase)
            if entry is None:
                errors.append(f"{prefix}: testcase {testcase} not in registry")
                continue
            mode = entry.get("mode")
            action = entry.get("gameday_action", "")
            defaults = entry.get("default_inputs", {}) or {}
            if mode not in {"read-only", "safe-gameday", "destructive"}:
                errors.append(f"{prefix}: testcase {testcase} has invalid mode {mode}")
                continue
            if mode == "safe-gameday":
                if not action:
                    errors.append(f"{prefix}: testcase {testcase} missing gameday_action")
                    continue
                script_path = repo_root / "ops" / "scripts" / "gameday" / f"gameday-{action}.sh"
                if not script_path.exists():
                    errors.append(f"{prefix}: gameday action script missing for {action}")
                required = required_inputs.get(action, [])
                for key in required:
                    if not defaults.get(key):
                        errors.append(f"{prefix}: testcase {testcase} missing default input {key}")

if errors:
    for err in errors:
        print(f"FAIL gameday mapping: {err}")
    sys.exit(1)

for contract_path in contracts:
    print(f"PASS gameday mapping: {contract_path}")
PY
