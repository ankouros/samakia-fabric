#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


contract=""
env_name="${ENV:-}"
storage="${TEMPLATE_STORAGE:-${STORAGE:-}}"
vmid="${TEMPLATE_VM_ID:-${VMID:-}}"
node="${TEMPLATE_NODE:-${PM_NODE:-}}"
name_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contract)
      contract="$2"
      shift 2
      ;;
    --env)
      env_name="$2"
      shift 2
      ;;
    --storage)
      storage="$2"
      shift 2
      ;;
    --vmid)
      vmid="$2"
      shift 2
      ;;
    --node)
      node="$2"
      shift 2
      ;;
    --name)
      name_override="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
 done

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $name" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd python3

if [[ -z "$contract" ]]; then
  echo "ERROR: --contract is required" >&2
  exit 2
fi

if [[ -z "$env_name" ]]; then
  echo "ERROR: --env (or ENV) is required" >&2
  exit 2
fi

if [[ -z "$storage" ]]; then
  echo "ERROR: --storage (or TEMPLATE_STORAGE/STORAGE) is required" >&2
  exit 2
fi

if [[ -z "$vmid" ]]; then
  echo "ERROR: --vmid (or TEMPLATE_VM_ID/VMID) is required" >&2
  exit 2
fi

if [[ -z "$node" ]]; then
  echo "ERROR: --node (or TEMPLATE_NODE/PM_NODE) is required" >&2
  exit 2
fi

if [[ ! -f "$contract" ]]; then
  echo "ERROR: contract not found: $contract" >&2
  exit 1
fi

policy_path="${FABRIC_REPO_ROOT}/ops/images/vm/register/register-policy.yml"
"${FABRIC_REPO_ROOT}/ops/images/vm/register/validate-register-policy.sh"
"${FABRIC_REPO_ROOT}/ops/images/vm/validate/validate-image-schema.sh"
"${FABRIC_REPO_ROOT}/ops/images/vm/validate/validate-image-semantics.sh"

contract_vars=$(python3 - <<'PY' "$contract" "$FABRIC_REPO_ROOT"
import json
import shlex
import sys
from pathlib import Path

contract_path = Path(sys.argv[1]).resolve()
repo_root = Path(sys.argv[2]).resolve()

data = json.loads(contract_path.read_text())
name = data["metadata"]["name"]
version = data["metadata"]["version"]
artifact = data.get("spec", {}).get("artifact", {})
sha256 = artifact.get("sha256", "")
fmt = artifact.get("format", "")

try:
    rel = contract_path.relative_to(repo_root)
    contract_rel = str(rel)
except ValueError:
    contract_rel = str(contract_path)

print(f"CONTRACT_NAME={shlex.quote(name)}")
print(f"CONTRACT_VERSION={shlex.quote(version)}")
print(f"CONTRACT_SHA256={shlex.quote(sha256)}")
print(f"CONTRACT_FORMAT={shlex.quote(fmt)}")
print(f"CONTRACT_REL={shlex.quote(contract_rel)}")
PY
)

while IFS= read -r line; do
  # shellcheck disable=SC2163
  [[ -n "${line}" ]] && export "${line}"
done <<< "${contract_vars}"

name_prefix=$(python3 - <<'PY' "$policy_path"
import json
from pathlib import Path

policy = json.loads(Path(sys.argv[1]).read_text())
print(policy.get("require", {}).get("template_name_prefix", ""))
PY
)

template_name="${name_override:-${name_prefix}${CONTRACT_NAME}-${CONTRACT_VERSION}}"

# Proxmox API auth
api_url="${PM_API_URL:-${TF_VAR_pm_api_url:-}}"
token_id="${PM_API_TOKEN_ID:-${TF_VAR_pm_api_token_id:-}}"
token_secret="${PM_API_TOKEN_SECRET:-${TF_VAR_pm_api_token_secret:-}}"

if [[ -z "${api_url}" || -z "${token_id}" || -z "${token_secret}" ]]; then
  echo "ERROR: missing Proxmox API token env vars (PM_API_URL/PM_API_TOKEN_ID/PM_API_TOKEN_SECRET or TF_VAR_* equivalents)." >&2
  exit 1
fi

if [[ "${api_url}" != https://* ]]; then
  echo "ERROR: Proxmox API URL must be https:// (strict TLS): ${api_url}" >&2
  exit 1
fi

if [[ "${token_id}" != *"!"* ]]; then
  echo "ERROR: Proxmox token id must include '!': ${token_id}" >&2
  exit 1
fi

bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/check-proxmox-ca-and-tls.sh" >/dev/null

if [[ "${api_url}" != */api2/json ]]; then
  api_url="${api_url%/}/api2/json"
fi

api_host=$(python3 - <<'PY' "$api_url"
import sys
from urllib.parse import urlparse

url = sys.argv[1]
parsed = urlparse(url)
print(parsed.hostname or "")
PY
)

if [[ -z "${api_host}" ]]; then
  echo "ERROR: failed to parse API host from PM_API_URL: ${api_url}" >&2
  exit 1
fi

python3 - <<'PY' "$policy_path" "$env_name" "$api_host" "$storage" "$template_name"
import json
import sys
from pathlib import Path

policy_path, env_name, api_host, storage, template_name = sys.argv[1:]
policy = json.loads(Path(policy_path).read_text())
allow = policy.get("allow", {})
require = policy.get("require", {})

envs = allow.get("envs", [])
if env_name not in envs:
    print(f"ERROR: ENV '{env_name}' not allowlisted in register-policy.yml", file=sys.stderr)
    sys.exit(1)

hosts = allow.get("api_hosts", [])
if api_host not in hosts:
    print(f"ERROR: Proxmox API host '{api_host}' not allowlisted in register-policy.yml", file=sys.stderr)
    sys.exit(1)

storages = allow.get("storage_ids", [])
if storage not in storages:
    print(f"ERROR: storage '{storage}' not allowlisted in register-policy.yml", file=sys.stderr)
    sys.exit(1)

prefix = require.get("template_name_prefix", "")
if prefix and not template_name.startswith(prefix):
    print(f"ERROR: template name '{template_name}' does not start with required prefix '{prefix}'", file=sys.stderr)
    sys.exit(1)
PY

require_prefixes=$(python3 - <<'PY' "$policy_path"
import json
from pathlib import Path

policy = json.loads(Path(sys.argv[1]).read_text())
print(" ".join(policy.get("allow", {}).get("tag_prefixes", [])))
PY
)

api_base="${api_url%/}"
auth_header="Authorization: PVEAPIToken=${token_id}=${token_secret}"

api_get() {
  local path="$1"
  curl -fsS -H "$auth_header" "${api_base}${path}"
}

# Ensure VM exists and is a template
is_template=$(api_get "/nodes/${node}/qemu" | python3 -c 'import json,sys; vmid=sys.argv[1]; payload=json.load(sys.stdin); result="missing";\nfor item in payload.get("data", []):\n    if str(item.get("vmid")) == vmid:\n        result=str(item.get("template", 0));\n        break\nprint(result)' "$vmid")

if [[ "$is_template" == "missing" ]]; then
  echo "ERROR: VMID ${vmid} not found on node ${node}" >&2
  exit 1
fi

if [[ "$is_template" != "1" ]]; then
  echo "ERROR: VMID ${vmid} exists but is not a template" >&2
  exit 1
fi

config=$(api_get "/nodes/${node}/qemu/${vmid}/config")

config_tags=$(printf '%s' "$config" | python3 -c 'import json,sys; payload=json.load(sys.stdin); print(payload.get("data", {}).get("tags", ""))')

config_desc=$(printf '%s' "$config" | python3 -c 'import json,sys; payload=json.load(sys.stdin); print(payload.get("data", {}).get("description", ""))')

config_scsi=$(printf '%s' "$config" | python3 -c 'import json,sys; payload=json.load(sys.stdin); print(payload.get("data", {}).get("scsi0", ""))')

if [[ -z "$config_scsi" ]]; then
  echo "ERROR: template does not have scsi0 attached" >&2
  exit 1
fi

python3 - <<'PY' "$config_tags" "$require_prefixes"
import sys

tags = sys.argv[1]
required = [x for x in sys.argv[2].split() if x]

prefixes = {t.split("=", 1)[0] for t in tags.split(";") if t}
missing = [p for p in required if p not in prefixes]
if missing:
    print(f"ERROR: template tags missing required prefixes: {missing}", file=sys.stderr)
    sys.exit(1)
PY

if [[ "$config_desc" != *"${CONTRACT_REL}"* ]]; then
  echo "ERROR: template description missing contract reference" >&2
  exit 1
fi

if [[ "$config_desc" != *"${CONTRACT_SHA256}"* ]]; then
  echo "ERROR: template description missing contract sha256" >&2
  exit 1
fi

# Evidence packet
"${FABRIC_REPO_ROOT}/ops/images/vm/register/register-evidence.sh" \
  --mode verify \
  --image "${CONTRACT_NAME}" \
  --version "${CONTRACT_VERSION}" \
  --contract "${contract}" \
  --env "${env_name}" \
  --storage "${storage}" \
  --vmid "${vmid}" \
  --node "${node}" \
  --name "${template_name}" \
  --sha256 "${CONTRACT_SHA256}" \
  --tags "${config_tags}" \
  --notes "${config_desc}" \
  --api-host "${api_host}"
