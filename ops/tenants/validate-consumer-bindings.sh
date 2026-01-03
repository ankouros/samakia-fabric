#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


TENANTS_ROOT="${FABRIC_REPO_ROOT}/contracts/tenants"
TESTCASES_FILE="${FABRIC_REPO_ROOT}/contracts/tenants/_schema/dr-testcases.yml"
SUBSTRATE_TESTCASES_FILE="${FABRIC_REPO_ROOT}/contracts/substrate/dr-testcases.yml"

if [[ ! -d "${TENANTS_ROOT}" ]]; then
  echo "ERROR: tenants directory not found: ${TENANTS_ROOT}" >&2
  exit 1
fi

if [[ ! -f "${TESTCASES_FILE}" ]]; then
  echo "ERROR: dr testcases list missing: ${TESTCASES_FILE}" >&2
  exit 1
fi

if [[ ! -f "${SUBSTRATE_TESTCASES_FILE}" ]]; then
  echo "ERROR: substrate dr testcases list missing: ${SUBSTRATE_TESTCASES_FILE}" >&2
  exit 1
fi

TENANTS_ROOT="${TENANTS_ROOT}" TESTCASES_FILE="${TESTCASES_FILE}" SUBSTRATE_TESTCASES_FILE="${SUBSTRATE_TESTCASES_FILE}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

tenants_root = Path(os.environ["TENANTS_ROOT"])
testcases_path = Path(os.environ["TESTCASES_FILE"])
substrate_testcases_path = Path(os.environ["SUBSTRATE_TESTCASES_FILE"])

errors = []


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        errors.append(f"{path}: invalid JSON ({exc})")
        return None


testcases = load_json(testcases_path)
if not isinstance(testcases, list) or not testcases:
    errors.append(f"{testcases_path}: invalid or empty testcase list")
    testcases = []

def flatten_substrate(data):
    cases = set()
    if not isinstance(data, dict):
        return cases
    for key, value in data.items():
        if isinstance(value, list):
            cases.update(item for item in value if isinstance(item, str))
        elif isinstance(value, dict):
            for subval in value.values():
                if isinstance(subval, list):
                    cases.update(item for item in subval if isinstance(item, str))
    return cases

substrate_raw = load_json(substrate_testcases_path)
substrate_cases = flatten_substrate(substrate_raw)
if not substrate_cases:
    errors.append(f"{substrate_testcases_path}: invalid or empty testcase list")


def endpoint_refs(tenant_dir: Path):
    endpoints_path = tenant_dir / "endpoints.yml"
    if not endpoints_path.exists():
        return set(), endpoints_path
    data = load_json(endpoints_path)
    if not data:
        return set(), endpoints_path
    refs = {ep.get("name") for ep in data.get("spec", {}).get("endpoints", []) if isinstance(ep, dict)}
    return {ref for ref in refs if ref}, endpoints_path


for ready in tenants_root.rglob("consumers/**/ready.yml"):
    binding = load_json(ready)
    if not binding:
        continue
    spec = binding.get("spec", {})
    if spec.get("ha_ready") is not True:
        errors.append(f"{ready}: ha_ready must be true")
    dr = spec.get("dr_testcases", [])
    if not isinstance(dr, list) or not dr:
        errors.append(f"{ready}: dr_testcases must be a non-empty list")
    else:
        unknown = [case for case in dr if case not in testcases]
        if unknown:
            errors.append(f"{ready}: unknown dr_testcases {unknown}")

for enabled in tenants_root.rglob("consumers/**/enabled.yml"):
    binding = load_json(enabled)
    if not binding:
        continue
    spec = binding.get("spec")
    if isinstance(spec, dict):
        if spec.get("ha_ready") is not True:
            errors.append(f"{enabled}: ha_ready must be true")
        mode = spec.get("mode")
        if mode not in {"dry-run", "execute"}:
            errors.append(f"{enabled}: mode must be dry-run or execute")
        dr = spec.get("dr_testcases", [])
        if not isinstance(dr, list) or not dr:
            errors.append(f"{enabled}: dr_testcases must be a non-empty list")
        else:
            unknown = [case for case in dr if case not in testcases]
            if unknown:
                errors.append(f"{enabled}: unknown dr_testcases {unknown}")
        restore_tests = spec.get("restore_testcases", [])
        if not isinstance(restore_tests, list) or not restore_tests:
            errors.append(f"{enabled}: restore_testcases must be a non-empty list")
        else:
            unknown = [case for case in restore_tests if case not in testcases]
            if unknown:
                errors.append(f"{enabled}: unknown restore_testcases {unknown}")

        endpoint_ref = spec.get("endpoint_ref")
        if not endpoint_ref:
            errors.append(f"{enabled}: endpoint_ref is required")
        tenant_dir = enabled.parents[2] if "consumers" in enabled.parts else enabled.parent
        refs, endpoints_path = endpoint_refs(tenant_dir)
        if endpoint_ref and endpoint_ref not in refs:
            errors.append(f"{enabled}: endpoint_ref '{endpoint_ref}' not found in {endpoints_path}")
    else:
        if binding.get("ha_ready") is not True:
            errors.append(f"{enabled}: ha_ready must be true")
        slo = binding.get("slo", {})
        tier = slo.get("tier")
        if not isinstance(tier, str) or not tier:
            errors.append(f"{enabled}: slo.tier must be a non-empty string")
        failure = binding.get("failure_semantics", {})
        mode = failure.get("mode")
        expectations = failure.get("expectations")
        if not isinstance(mode, str) or not mode:
            errors.append(f"{enabled}: failure_semantics.mode must be a non-empty string")
        if not isinstance(expectations, str) or not expectations.strip():
            errors.append(f"{enabled}: failure_semantics.expectations must be a non-empty string")
        variant = binding.get("variant")
        if variant == "single" and mode != "spof":
            errors.append(f"{enabled}: failure_semantics.mode must be spof for single variant")
        if variant == "cluster" and mode != "failover":
            errors.append(f"{enabled}: failure_semantics.mode must be failover for cluster variant")
        executor = binding.get("executor", {})
        if executor.get("mode") not in {"dry-run", "execute"}:
            errors.append(f"{enabled}: executor.mode must be dry-run or execute")
        dr = binding.get("dr", {}).get("required_testcases", [])
        if not isinstance(dr, list) or not dr:
            errors.append(f"{enabled}: dr.required_testcases must be a non-empty list")
        else:
            unknown = [case for case in dr if case not in substrate_cases]
            if unknown:
                errors.append(f"{enabled}: unknown dr.required_testcases {unknown}")
        dr_root = binding.get("dr", {})
        if not isinstance(dr_root.get("rpo_target"), str) or not dr_root.get("rpo_target"):
            errors.append(f"{enabled}: dr.rpo_target must be a non-empty string")
        if not isinstance(dr_root.get("rto_target"), str) or not dr_root.get("rto_target"):
            errors.append(f"{enabled}: dr.rto_target must be a non-empty string")
        endpoints = binding.get("endpoints", {})
        host = endpoints.get("host")
        port = endpoints.get("port")
        if not isinstance(host, str) or not host.strip():
            errors.append(f"{enabled}: endpoints.host must be a non-empty string")
        if not isinstance(port, int):
            errors.append(f"{enabled}: endpoints.port must be an integer")
        secret_ref = binding.get("secret_ref")
        if not isinstance(secret_ref, str) or not secret_ref.strip():
            errors.append(f"{enabled}: secret_ref must be a non-empty string")

if errors:
    for err in errors:
        print(f"FAIL bindings: {err}")
    sys.exit(1)

for ready in tenants_root.rglob("consumers/**/ready.yml"):
    print(f"PASS bindings: {ready}")
for enabled in tenants_root.rglob("consumers/**/enabled.yml"):
    print(f"PASS bindings: {enabled}")
PY
