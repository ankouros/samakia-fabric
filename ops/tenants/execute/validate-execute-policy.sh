#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


policy_file="${FABRIC_REPO_ROOT}/ops/tenants/execute/execute-policy.yml"

if [[ ! -f "${policy_file}" ]]; then
  echo "ERROR: execute policy missing: ${policy_file}" >&2
  exit 1
fi

POLICY_FILE="${policy_file}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

policy_path = Path(os.environ["POLICY_FILE"])

try:
    policy = json.loads(policy_path.read_text())
except json.JSONDecodeError as exc:
    print(f"ERROR: invalid JSON in {policy_path}: {exc}", file=sys.stderr)
    sys.exit(1)

errors = []

required_keys = [
    "allowed_envs",
    "allowed_tenants",
    "allowed_consumers",
    "require_reason",
    "require_change_window_for_prod",
    "require_signing_for_prod",
    "require_signing_for_shared",
]

for key in required_keys:
    if key not in policy:
        errors.append(f"missing key: {key}")

allowed_envs = policy.get("allowed_envs", [])
if not isinstance(allowed_envs, list) or not allowed_envs:
    errors.append("allowed_envs must be a non-empty list")
if "samakia-prod" in allowed_envs:
    errors.append("samakia-prod must not be allowlisted for execute")

allowed_tenants = policy.get("allowed_tenants", [])
if not isinstance(allowed_tenants, list):
    errors.append("allowed_tenants must be a list")

allowed_consumers = policy.get("allowed_consumers", [])
if not isinstance(allowed_consumers, list) or not allowed_consumers:
    errors.append("allowed_consumers must be a non-empty list")

for key in ("require_reason", "require_change_window_for_prod", "require_signing_for_prod", "require_signing_for_shared"):
    if key in policy and not isinstance(policy[key], bool):
        errors.append(f"{key} must be boolean")

if errors:
    for err in errors:
        print(f"FAIL execute policy: {err}")
    sys.exit(1)

print(f"PASS execute policy: {policy_path}")
PY
