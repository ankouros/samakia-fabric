#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

policy_path="${FABRIC_REPO_ROOT}/ops/images/vm/register/register-policy.yml"

if [[ ! -f "$policy_path" ]]; then
  echo "ERROR: register policy not found: $policy_path" >&2
  exit 1
fi

POLICY_PATH="$policy_path" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

policy_path = Path(os.environ["POLICY_PATH"])
try:
    policy = json.loads(policy_path.read_text())
except json.JSONDecodeError as exc:
    print(f"ERROR: policy is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(1)

allow = policy.get("allow", {})
require = policy.get("require", {})

errors = []

envs = allow.get("envs", [])
if not isinstance(envs, list) or not envs:
    errors.append("allow.envs must be a non-empty list")
if "samakia-prod" in envs:
    errors.append("allow.envs must not include samakia-prod")

api_hosts = allow.get("api_hosts", [])
if not isinstance(api_hosts, list) or not api_hosts:
    errors.append("allow.api_hosts must be a non-empty list")

storage_ids = allow.get("storage_ids", [])
if not isinstance(storage_ids, list) or not storage_ids:
    errors.append("allow.storage_ids must be a non-empty list")

tag_prefixes = allow.get("tag_prefixes", [])
if not isinstance(tag_prefixes, list) or not tag_prefixes:
    errors.append("allow.tag_prefixes must be a non-empty list")

name_prefix = require.get("template_name_prefix", "")
if not isinstance(name_prefix, str) or not name_prefix:
    errors.append("require.template_name_prefix must be a non-empty string")

req_tags = require.get("tags", [])
if not isinstance(req_tags, list) or not req_tags:
    errors.append("require.tags must be a non-empty list")

if errors:
    for err in errors:
        print(f"ERROR: {err}", file=sys.stderr)
    sys.exit(1)

print("PASS: register-policy.yml is valid")
PY
