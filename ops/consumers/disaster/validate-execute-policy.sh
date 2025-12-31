#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

policy_path="${FABRIC_REPO_ROOT}/ops/consumers/disaster/execute-policy.yml"

if [[ ! -f "${policy_path}" ]]; then
  echo "ERROR: execute policy not found: ${policy_path}" >&2
  exit 1
fi

python3 - "${policy_path}" <<'PY'
import json
import sys
from pathlib import Path

policy = json.loads(Path(sys.argv[1]).read_text())

errors = []

allowlist = policy.get("allowlist", {})
envs = allowlist.get("envs", [])
actions = allowlist.get("actions", [])
consumer_types = allowlist.get("consumer_types", [])

if "samakia-prod" in envs:
    errors.append("execute policy must not allow samakia-prod")

allowed_actions = {"vip-failover", "service-restart"}
for action in actions:
    if action not in allowed_actions:
        errors.append(f"execute policy includes unsupported or destructive action: {action}")

if not envs:
    errors.append("execute policy allowlist.envs is empty")
if not actions:
    errors.append("execute policy allowlist.actions is empty")
if not consumer_types:
    errors.append("execute policy allowlist.consumer_types is empty")

maintenance = policy.get("maintenance_window", {})
max_minutes = maintenance.get("max_minutes")
if max_minutes is None or not isinstance(max_minutes, int) or max_minutes <= 0:
    errors.append("maintenance_window.max_minutes must be a positive integer")

reason_min = policy.get("reason_min_length")
if reason_min is None or not isinstance(reason_min, int) or reason_min < 8:
    errors.append("reason_min_length must be an integer >= 8")

signing = policy.get("signing", {})
require_sign = signing.get("require_execute_signing")
allow_unsigned = signing.get("allow_unsigned_execute")
if require_sign and allow_unsigned:
    errors.append("signing policy cannot require and allow unsigned execute simultaneously")

if errors:
    for err in errors:
        print(f"FAIL execute policy: {err}")
    sys.exit(1)

print("PASS execute policy: allowlist + signing + maintenance window constraints OK")
PY
