#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


mapfile -t contracts < <(find "${FABRIC_REPO_ROOT}/contracts/consumers" -mindepth 2 -maxdepth 2 -name "*.yml" -print | sort)

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
    ha = spec.get("ha", {})
    tier = ha.get("tier")
    replicas = ha.get("replicas_min")
    anti = ha.get("anti_affinity")
    domains = ha.get("failure_domains", [])

    prefix = contract.name

    if tier not in {"tier0", "tier1", "tier2"}:
        errors.append(f"{prefix}: invalid ha.tier {tier}")
        continue
    if anti is not True:
        errors.append(f"{prefix}: ha.anti_affinity must be true")
    if not isinstance(replicas, int):
        errors.append(f"{prefix}: ha.replicas_min must be integer")
    if tier in {"tier0", "tier1"} and replicas is not None and replicas < 2:
        errors.append(f"{prefix}: tier0/tier1 require replicas_min >= 2")
    if not domains:
        errors.append(f"{prefix}: failure_domains must be declared")
    if isinstance(replicas, int) and domains and len(domains) < min(replicas, 2):
        errors.append(f"{prefix}: failure_domains count too small for replicas_min")

if errors:
    for err in errors:
        print(f"FAIL ha: {err}")
    sys.exit(1)

for contract in contracts:
    print(f"PASS ha: {contract}")
PY
