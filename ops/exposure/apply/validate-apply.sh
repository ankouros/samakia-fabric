#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  echo "usage: validate-apply.sh TENANT=<id> WORKLOAD=<id> ENV=<env> APPROVAL_PATH=<path>" >&2
}

tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"
approval_path="${APPROVAL_PATH:-}"

if [[ -z "${tenant}" || -z "${workload}" || -z "${env_name}" || -z "${approval_path}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${approval_path}" ]]; then
  echo "ERROR: approval file not found: ${approval_path}" >&2
  exit 1
fi

bash "${FABRIC_REPO_ROOT}/ops/exposure/approve/validate-approval.sh" --approval "${approval_path}"

binding_contract="${FABRIC_REPO_ROOT}/contracts/bindings/tenants/${tenant}/${workload}.binding.yml"
if [[ ! -f "${binding_contract}" ]]; then
  echo "ERROR: binding contract not found: ${binding_contract}" >&2
  exit 1
fi

binding_manifest="${FABRIC_REPO_ROOT}/artifacts/bindings/${tenant}/${workload}/connection.json"
if [[ ! -f "${binding_manifest}" ]]; then
  echo "ERROR: binding manifest not found: ${binding_manifest}" >&2
  echo "Hint: run 'make bindings.render TENANT=${tenant}'" >&2
  exit 1
fi

BINDING_CONTRACT="${binding_contract}" python3 - <<'PY'
import os
import sys
from pathlib import Path
import yaml

path = Path(os.environ["BINDING_CONTRACT"])
contract = yaml.safe_load(path.read_text())

consumers = contract.get("spec", {}).get("consumers", [])
if not consumers:
    raise SystemExit("ERROR: binding consumers missing")

missing = []
for idx, consumer in enumerate(consumers, start=1):
    ref = consumer.get("secret_ref")
    if not ref:
        missing.append(f"consumer[{idx}]: secret_ref missing")

if missing:
    for entry in missing:
        print(f"ERROR: {entry}", file=sys.stderr)
    raise SystemExit("ERROR: one or more secret_ref entries missing")

print(f"PASS: secret_ref entries present for {path}")
PY
