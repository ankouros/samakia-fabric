#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

schema_path="${FABRIC_REPO_ROOT}/contracts/proposals/proposal.schema.json"
if [[ ! -f "${schema_path}" ]]; then
  echo "ERROR: proposal schema missing: ${schema_path}" >&2
  exit 1
fi

proposal_id="${PROPOSAL_ID:-}"
file_override="${FILE:-}"
validation_out="${VALIDATION_OUT:-}"

collect_files=()
if [[ -n "${file_override}" ]]; then
  collect_files+=("${file_override}")
elif [[ "${proposal_id}" == "example" ]]; then
  while IFS= read -r path; do
    collect_files+=("${path}")
  done < <(find "${FABRIC_REPO_ROOT}/examples/proposals" -type f -name "*.yml" -print | sort)
elif [[ -n "${proposal_id}" ]]; then
  inbox_match=$(find "${FABRIC_REPO_ROOT}/proposals/inbox" -type f -name "proposal.yml" -path "*/${proposal_id}/*" 2>/dev/null | head -n1 || true)
  if [[ -n "${inbox_match}" ]]; then
    collect_files+=("${inbox_match}")
  elif [[ -f "${FABRIC_REPO_ROOT}/examples/proposals/${proposal_id}.yml" ]]; then
    collect_files+=("${FABRIC_REPO_ROOT}/examples/proposals/${proposal_id}.yml")
  else
    echo "ERROR: proposal not found for PROPOSAL_ID=${proposal_id}" >&2
    exit 1
  fi
else
  echo "ERROR: set PROPOSAL_ID=<id>|example or FILE=<path>" >&2
  exit 1
fi

if [[ ${#collect_files[@]} -eq 0 ]]; then
  echo "ERROR: no proposal files found" >&2
  exit 1
fi

status=0
for proposal_path in "${collect_files[@]}"; do
  if [[ ! -f "${proposal_path}" ]]; then
    echo "ERROR: proposal file missing: ${proposal_path}" >&2
    status=1
    continue
  fi
  tenant_dir=""
  if [[ "${proposal_path}" == *"/proposals/inbox/"*"/proposal.yml" ]]; then
    tenant_dir=$(basename "$(dirname "$(dirname "${proposal_path}")")")
  fi
  if ! validation_json=$(SCHEMA_PATH="${schema_path}" PROPOSAL_PATH="${proposal_path}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" TENANT_DIR="${tenant_dir}" python3 - <<'PY'
import json
import os
import re
import sys
from pathlib import Path
import yaml

schema_path = Path(os.environ["SCHEMA_PATH"])
proposal_path = Path(os.environ["PROPOSAL_PATH"])
repo_root = Path(os.environ["FABRIC_REPO_ROOT"])
tenant_dir = os.environ.get("TENANT_DIR") or ""

schema = json.loads(schema_path.read_text())
proposal = yaml.safe_load(proposal_path.read_text())

errors = []

def type_ok(value, expected):
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int)
    if expected == "number":
        return isinstance(value, (int, float))
    if expected == "boolean":
        return isinstance(value, bool)
    return True

def validate(data, schema_obj, path="$"):
    if "type" in schema_obj:
        if not type_ok(data, schema_obj["type"]):
            errors.append(f"{path}: expected {schema_obj['type']}")
            return False
    if "const" in schema_obj:
        if data != schema_obj["const"]:
            errors.append(f"{path}: expected const {schema_obj['const']}")
            return False
    if "enum" in schema_obj:
        if data not in schema_obj["enum"]:
            errors.append(f"{path}: value {data} not in {schema_obj['enum']}")
            return False
    if schema_obj.get("type") == "object":
        required = schema_obj.get("required", [])
        for key in required:
            if key not in data:
                errors.append(f"{path}: missing required key {key}")
                return False
        props = schema_obj.get("properties", {})
        additional = schema_obj.get("additionalProperties", True)
        if additional is False:
            for key in data:
                if key not in props:
                    errors.append(f"{path}: unknown key {key}")
                    return False
        for key, val in data.items():
            if key in props:
                if not validate(val, props[key], f"{path}.{key}"):
                    return False
    if schema_obj.get("type") == "array":
        item_schema = schema_obj.get("items")
        if item_schema:
            for idx, item in enumerate(data):
                if not validate(item, item_schema, f"{path}[{idx}]"):
                    return False
    return True

if not isinstance(proposal, dict):
    errors.append("proposal: expected mapping")
else:
    validate(proposal, schema)

if tenant_dir:
    if proposal.get("tenant_id") != tenant_dir:
        errors.append(f"tenant mismatch: {proposal.get('tenant_id')} != {tenant_dir}")

justification = proposal.get("justification", "") if isinstance(proposal, dict) else ""
if isinstance(justification, str) and len(justification.strip()) < 5:
    errors.append("justification must be at least 5 characters")

scope = proposal.get("scope", {}) if isinstance(proposal, dict) else {}
if isinstance(scope, dict):
    if not any(scope.get(key) for key in ("bindings", "capacity", "rotation")):
        errors.append("scope: at least one of bindings/capacity/rotation must be true")

secret_re = re.compile(
    r"(AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH) PRIVATE KEY|\b(password|token|secret)\b\s*[:=]\s*\S+)",
    re.IGNORECASE,
)

def scan(value):
    if isinstance(value, str):
        if secret_re.search(value):
            errors.append("proposal contains secret-like value")
    elif isinstance(value, dict):
        for v in value.values():
            scan(v)
    elif isinstance(value, list):
        for v in value:
            scan(v)

scan(proposal)

changes = proposal.get("changes", []) if isinstance(proposal, dict) else []
if isinstance(changes, list):
    for change in changes:
        if not isinstance(change, dict):
            errors.append("changes entries must be objects")
            continue
        kind = change.get("kind")
        target = change.get("target")
        if not isinstance(target, str):
            errors.append("change target must be string")
            continue
        target_path = (repo_root / target).resolve() if not Path(target).is_absolute() else Path(target)
        if kind in {"binding", "capacity"}:
            if not target_path.exists():
                errors.append(f"target not found: {target}")
            if proposal.get("tenant_id") and f"/{proposal.get('tenant_id')}/" not in str(target_path):
                errors.append(f"target not under tenant: {target}")
        if kind == "binding" and not str(target_path).endswith(".binding.yml"):
            errors.append(f"binding target must be .binding.yml: {target}")
        if kind == "capacity" and not str(target_path).endswith("capacity.yml"):
            errors.append(f"capacity target must be capacity.yml: {target}")

result = {
    "proposal": proposal.get("proposal_id"),
    "path": str(proposal_path),
    "status": "PASS" if not errors else "FAIL",
    "errors": errors,
}
print(json.dumps(result, indent=2, sort_keys=True))
if errors:
    sys.exit(1)
PY
); then
    status=1
  else
    status=0
  fi
  if [[ -n "${validation_out}" ]]; then
    mkdir -p "$(dirname "${validation_out}")"
    printf '%s\n' "${validation_json}" >"${validation_out}"
  fi
  if [[ ${status} -ne 0 ]]; then
    echo "FAIL proposal validation: ${proposal_path}" >&2
  else
    echo "PASS proposal validation: ${proposal_path}"
  fi
  if [[ ${status} -ne 0 ]]; then
    exit 1
  fi

  if [[ "${proposal_id}" != "example" ]]; then
    read -r cap_tenant cap_flag < <(PROPOSAL_PATH="${proposal_path}" python3 - <<'PY'
import os
import yaml
from pathlib import Path
proposal = yaml.safe_load(Path(os.environ["PROPOSAL_PATH"]).read_text())
tenant = proposal.get("tenant_id", "") if isinstance(proposal, dict) else ""
changes = proposal.get("changes", []) if isinstance(proposal, dict) else []
capacity = proposal.get("scope", {}).get("capacity") if isinstance(proposal, dict) else False
has_capacity = bool(capacity) or any(isinstance(c, dict) and c.get("kind") == "capacity" for c in changes)
print(tenant, "1" if has_capacity else "0")
PY
)
    if [[ "${cap_flag}" == "1" && -n "${cap_tenant}" ]]; then
      make -C "${FABRIC_REPO_ROOT}" tenants.capacity.validate TENANT="${cap_tenant}"
    fi
  fi

done
