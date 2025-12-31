#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

mapfile -t contracts < <(find "${FABRIC_REPO_ROOT}/contracts/consumers" -mindepth 2 -maxdepth 2 -name "*.yml" -print | sort)

if [[ ${#contracts[@]} -eq 0 ]]; then
  echo "ERROR: no consumer contracts found" >&2
  exit 1
fi

CONTRACTS_LIST="$(printf '%s\n' "${contracts[@]}")" python3 - <<'PY'
import json
import sys
import os
from pathlib import Path

contracts = [Path(p) for p in os.environ["CONTRACTS_LIST"].splitlines() if p]

errors = []

for contract in contracts:
    data = json.loads(contract.read_text())
    spec = data.get("spec", {})
    variant = spec.get("variant")
    ha = spec.get("ha", {})
    network = spec.get("network", {})
    firewall = spec.get("firewall", {})
    observability = spec.get("observability", {})
    disaster = spec.get("disaster", {})
    secrets = spec.get("secrets")

    prefix = contract.name

    if firewall.get("default_off") is not True:
        errors.append(f"{prefix}: firewall.default_off must be true")

    if ha.get("anti_affinity") is not True:
        errors.append(f"{prefix}: ha.anti_affinity must be true")

    if not observability.get("metrics") or not observability.get("logs"):
        errors.append(f"{prefix}: observability intents must be declared")

    scenarios = disaster.get("scenarios", [])
    if not scenarios:
        errors.append(f"{prefix}: disaster.scenarios must be non-empty")

    vip = network.get("vip", {})
    vip_required = vip.get("required")

    if variant == "ready":
        if vip_required is True:
            errors.append(f"{prefix}: ready variant must not require VIP endpoints")
        if secrets:
            errors.append(f"{prefix}: ready variant must not declare secrets")
    elif variant == "enabled":
        if vip_required is not True:
            errors.append(f"{prefix}: enabled variant must require VIP endpoints")
        if not secrets or not secrets.get("required"):
            errors.append(f"{prefix}: enabled variant must declare secrets.required")
    else:
        errors.append(f"{prefix}: unknown variant {variant}")

if errors:
    for err in errors:
        print(f"FAIL semantics: {err}")
    sys.exit(1)

for contract in contracts:
    print(f"PASS semantics: {contract}")
PY
