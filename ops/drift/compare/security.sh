#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


TENANT="${TENANT:-}"
if [[ -z "${TENANT}" ]]; then
  echo "ERROR: TENANT is required" >&2
  exit 2
fi

FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" python3 - "${TENANT}" <<'PY'
import json
import os
import re
import sys
from pathlib import Path
import yaml

root = Path(os.environ["FABRIC_REPO_ROOT"])
tenant = sys.argv[1]

bindings_dir = root / "contracts" / "bindings" / "tenants" / tenant
render_root = root / "artifacts" / "bindings" / tenant

patterns = [
    re.compile(r"password", re.IGNORECASE),
    re.compile(r"token", re.IGNORECASE),
    re.compile(r"secret", re.IGNORECASE),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"BEGIN (RSA|OPENSSH) PRIVATE KEY"),
]

allowed_refs = re.compile(r"^(tenants/|vault://)")

issues = []
files = []


def load_yaml(path: Path):
    return yaml.safe_load(path.read_text())


def load_json(path: Path):
    return json.loads(path.read_text())


def scrub_value(value):
    if isinstance(value, str):
        if allowed_refs.search(value):
            return False
        for pattern in patterns:
            if pattern.search(value):
                return True
    return False


def walk(obj, path, source):
    if isinstance(obj, dict):
        for key, val in obj.items():
            walk(val, f"{path}.{key}" if path else str(key), source)
    elif isinstance(obj, list):
        for idx, val in enumerate(obj):
            walk(val, f"{path}[{idx}]", source)
    else:
        if scrub_value(obj):
            issues.append({"source": source, "path": path})


if bindings_dir.exists():
    for binding in sorted(bindings_dir.glob("*.binding.yml")):
        data = load_yaml(binding)
        files.append(str(binding))
        walk(data, "", str(binding))

if render_root.exists():
    for manifest in sorted(render_root.glob("*/connection.json")):
        data = load_json(manifest)
        files.append(str(manifest))
        walk(data, "", str(manifest))

status = "PASS"
if not files:
    status = "UNKNOWN"
    issues.append({"source": "none", "path": "no bindings or renders"})
elif issues:
    status = "FAIL"

result = {
    "tenant": tenant,
    "status": status,
    "files_scanned": len(files),
    "issues": issues,
}
print(json.dumps(result, sort_keys=True, indent=2))
PY
