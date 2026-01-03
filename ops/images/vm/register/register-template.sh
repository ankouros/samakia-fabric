#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


contract=""
qcow2=""
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
    --qcow2)
      qcow2="$2"
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
require_cmd sha256sum

if [[ -z "$contract" || -z "$qcow2" ]]; then
  echo "ERROR: --contract and --qcow2 are required" >&2
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

if [[ ! -f "$qcow2" ]]; then
  echo "ERROR: qcow2 not found: $qcow2" >&2
  exit 1
fi

if [[ ! "$vmid" =~ ^[0-9]+$ ]]; then
  echo "ERROR: vmid must be numeric: $vmid" >&2
  exit 2
fi

if [[ "${IMAGE_REGISTER:-0}" != "1" ]]; then
  echo "ERROR: IMAGE_REGISTER=1 is required to execute template registration" >&2
  exit 1
fi

if [[ "${I_UNDERSTAND_TEMPLATE_MUTATION:-0}" != "1" ]]; then
  echo "ERROR: I_UNDERSTAND_TEMPLATE_MUTATION=1 is required" >&2
  exit 1
fi

register_reason="${REGISTER_REASON:-}"
if [[ -z "$register_reason" || ${#register_reason} -lt 8 ]]; then
  echo "ERROR: REGISTER_REASON must be provided (min length 8)" >&2
  exit 1
fi

if [[ "${REGISTER_REPLACE:-0}" == "1" && "${I_UNDERSTAND_DESTRUCTIVE:-0}" != "1" ]]; then
  echo "ERROR: REGISTER_REPLACE=1 requires I_UNDERSTAND_DESTRUCTIVE=1" >&2
  exit 1
fi

policy_path="${FABRIC_REPO_ROOT}/ops/images/vm/register/register-policy.yml"
"${FABRIC_REPO_ROOT}/ops/images/vm/register/validate-register-policy.sh"
"${FABRIC_REPO_ROOT}/ops/images/vm/validate/validate-image-schema.sh"
"${FABRIC_REPO_ROOT}/ops/images/vm/validate/validate-image-semantics.sh"

# Extract contract metadata
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
storage_path = artifact.get("storage_path", "")

try:
    rel = contract_path.relative_to(repo_root)
    contract_rel = str(rel)
except ValueError:
    contract_rel = str(contract_path)

print(f"CONTRACT_NAME={shlex.quote(name)}")
print(f"CONTRACT_VERSION={shlex.quote(version)}")
print(f"CONTRACT_SHA256={shlex.quote(sha256)}")
print(f"CONTRACT_FORMAT={shlex.quote(fmt)}")
print(f"CONTRACT_STORAGE_PATH={shlex.quote(storage_path)}")
print(f"CONTRACT_REL={shlex.quote(contract_rel)}")
PY
)

while IFS= read -r line; do
  # shellcheck disable=SC2163
  [[ -n "${line}" ]] && export "${line}"
done <<< "${contract_vars}"

if [[ "${CONTRACT_FORMAT}" != "qcow2" ]]; then
  echo "ERROR: contract artifact format must be qcow2" >&2
  exit 1
fi

computed_sha=$(sha256sum "$qcow2" | awk '{print $1}')
computed_ref="sha256:${computed_sha}"

if [[ "${CONTRACT_SHA256}" == "sha256:<REPLACE_WITH_SHA256>" || "${CONTRACT_SHA256}" == "sha256:"*"<"* ]]; then
  echo "ERROR: contract sha256 is a placeholder. Update contract spec.artifact.sha256 to: ${computed_ref}" >&2
  exit 1
fi

if [[ "${CONTRACT_SHA256}" != "${computed_ref}" ]]; then
  echo "ERROR: qcow2 sha256 mismatch. Contract=${CONTRACT_SHA256} Computed=${computed_ref}" >&2
  exit 1
fi

name_prefix=$(python3 - <<'PY' "$policy_path"
import json
from pathlib import Path

policy = json.loads(Path(sys.argv[1]).read_text())
print(policy.get("require", {}).get("template_name_prefix", ""))
PY
)

template_name="${name_override:-${name_prefix}${CONTRACT_NAME}-${CONTRACT_VERSION}}"

if [[ -z "${template_name}" ]]; then
  echo "ERROR: template name could not be determined" >&2
  exit 1
fi

if [[ -n "${name_prefix}" && "${template_name}" != "${name_prefix}"* ]]; then
  echo "ERROR: template name must start with prefix '${name_prefix}'" >&2
  exit 1
fi

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

# Enforce strict TLS + token-only constraints (and verify host CA trust).
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

# Enforce policy allowlist
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

# Build tags and validate prefixes
require_prefixes=$(python3 - <<'PY' "$policy_path"
import json
from pathlib import Path

policy = json.loads(Path(sys.argv[1]).read_text())
print(" ".join(policy.get("allow", {}).get("tag_prefixes", [])))
PY
)

tags="golden=vm;image=${CONTRACT_NAME};version=${CONTRACT_VERSION};env=${env_name}"

python3 - <<'PY' "$tags" "$require_prefixes"
import sys

tags = sys.argv[1]
required = [x for x in sys.argv[2].split() if x]

prefixes = {t.split("=", 1)[0] for t in tags.split(";") if t}
missing = [p for p in required if p not in prefixes]
if missing:
    print(f"ERROR: tags missing required prefixes: {missing}", file=sys.stderr)
    sys.exit(1)
PY

notes="samakia_contract=${CONTRACT_REL};contract_sha=${CONTRACT_SHA256};qcow2_sha256=${computed_ref};registered_at=$(date -u +%Y-%m-%dT%H:%M:%SZ);env=${env_name}"

api_base="${api_url%/}"
auth_header="Authorization: PVEAPIToken=${token_id}=${token_secret}"

api_get() {
  local path="$1"
  curl -fsS -H "$auth_header" "${api_base}${path}"
}

api_post() {
  local path="$1"
  shift
  curl -fsS -H "$auth_header" -X POST "$@" "${api_base}${path}"
}

api_delete() {
  local path="$1"
  shift
  curl -fsS -H "$auth_header" -X DELETE "$@" "${api_base}${path}"
}

extract_upid() {
  python3 - <<'PY'
import json
import sys

payload = json.load(sys.stdin)
data = payload.get("data")
if isinstance(data, str) and data.startswith("UPID:"):
    print(data)
PY
}

wait_for_task() {
  local task_node="$1"
  local upid="$2"
  local encoded
  encoded=$(python3 - <<'PY' "$upid"
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=""))
PY
)
  local deadline=$(( $(date +%s) + 300 ))
  while true; do
    status=$(api_get "/nodes/${task_node}/tasks/${encoded}/status" | python3 -c 'import json,sys; payload=json.load(sys.stdin); status=payload.get("data", {}).get("status"); exitstatus=payload.get("data", {}).get("exitstatus"); print(f"{status}|{exitstatus}")')
    state="${status%%|*}"
    exitstatus="${status##*|}"
    if [[ "$state" == "stopped" ]]; then
      if [[ "$exitstatus" == "OK" ]]; then
        return 0
      fi
      echo "ERROR: Proxmox task failed (exitstatus=${exitstatus})" >&2
      return 1
    fi
    if [[ $(date +%s) -ge $deadline ]]; then
      echo "ERROR: Proxmox task timed out" >&2
      return 1
    fi
    sleep 2
  done
}

# Check for existing VMID
vm_exists=$(api_get "/nodes/${node}/qemu" | python3 -c 'import json,sys; vmid=sys.argv[1]; payload=json.load(sys.stdin); found="no";\nfor item in payload.get("data", []):\n    if str(item.get("vmid")) == vmid:\n        found="yes";\n        break\nprint(found)' "$vmid")

if [[ "$vm_exists" == "yes" ]]; then
  if [[ "${REGISTER_REPLACE:-0}" != "1" ]]; then
    echo "ERROR: VMID ${vmid} already exists. Set REGISTER_REPLACE=1 and I_UNDERSTAND_DESTRUCTIVE=1 to replace." >&2
    exit 1
  fi
  echo "WARN: VMID ${vmid} exists; destructive replace requested." >&2
  resp=$(api_delete "/nodes/${node}/qemu/${vmid}" --data-urlencode "purge=1" --data-urlencode "destroy-unreferenced-disks=1")
  upid=$(printf '%s' "$resp" | extract_upid)
  if [[ -n "$upid" ]]; then
    wait_for_task "$node" "$upid"
  fi
fi

# Ensure qcow2 does not already exist in ISO storage
qcow2_name="$(basename "$qcow2")"
iso_exists=$(api_get "/nodes/${node}/storage/${storage}/content" | python3 -c 'import json,sys; storage=sys.argv[1]; name=sys.argv[2]; payload=json.load(sys.stdin); volid=f"{storage}:iso/{name}"; found="no";\nfor item in payload.get("data", []):\n    if item.get("volid") == volid:\n        found="yes";\n        break\nprint(found)' "$storage" "$qcow2_name")

if [[ "$iso_exists" == "yes" ]]; then
  echo "ERROR: qcow2 already present in storage as iso/${qcow2_name}. Remove it or rename qcow2 before retry." >&2
  exit 1
fi

# Upload qcow2 to ISO content for import
upload_url="${api_base}/nodes/${node}/storage/${storage}/upload"
curl -fsS -H "$auth_header" -X POST -F "content=iso" -F "filename=@${qcow2}" "$upload_url" >/dev/null

# Create VM shell
mem_mb="${TEMPLATE_MEMORY_MB:-1024}"
cores="${TEMPLATE_CORES:-1}"
sockets="${TEMPLATE_SOCKETS:-1}"
bridge="${TEMPLATE_NET_BRIDGE:-vmbr0}"

resp=$(api_post "/nodes/${node}/qemu" \
  --data-urlencode "vmid=${vmid}" \
  --data-urlencode "name=${template_name}" \
  --data-urlencode "memory=${mem_mb}" \
  --data-urlencode "cores=${cores}" \
  --data-urlencode "sockets=${sockets}" \
  --data-urlencode "ostype=l26" \
  --data-urlencode "agent=1" \
  --data-urlencode "scsihw=virtio-scsi-pci" \
  --data-urlencode "net0=virtio,bridge=${bridge}" \
  --data-urlencode "serial0=socket" \
  --data-urlencode "vga=serial0")

upid=$(printf '%s' "$resp" | extract_upid)
if [[ -n "$upid" ]]; then
  wait_for_task "$node" "$upid"
fi

# Import disk
resp=$(api_post "/nodes/${node}/qemu/${vmid}/importdisk" \
  --data-urlencode "filename=${storage}:iso/${qcow2_name}" \
  --data-urlencode "storage=${storage}" \
  --data-urlencode "format=qcow2")

volid=$(printf '%s' "$resp" | python3 -c 'import json,sys; payload=json.load(sys.stdin); data=payload.get("data");\nif isinstance(data, str):\n    print("" if data.startswith("UPID:") else data)\nelif isinstance(data, dict):\n    print(data.get("volid", ""))\nelse:\n    print("")')

upid=$(printf '%s' "$resp" | extract_upid)
if [[ -n "$upid" ]]; then
  wait_for_task "$node" "$upid"
fi

if [[ -z "$volid" ]]; then
  volid=$(api_get "/nodes/${node}/qemu/${vmid}/config" | python3 -c 'import json,sys; payload=json.load(sys.stdin); config=payload.get("data", {}); \nfor key in sorted(config.keys()):\n    if key.startswith("unused"):\n        print(config[key]);\n        sys.exit(0)\nprint("")')
fi

if [[ -z "$volid" ]]; then
  echo "ERROR: failed to locate imported disk volume for VMID ${vmid}" >&2
  exit 1
fi

# Attach disk + cloud-init + notes/tags
resp=$(api_post "/nodes/${node}/qemu/${vmid}/config" \
  --data-urlencode "scsi0=${volid}" \
  --data-urlencode "boot=order=scsi0" \
  --data-urlencode "ide2=${storage}:cloudinit" \
  --data-urlencode "tags=${tags}" \
  --data-urlencode "description=${notes}")
upid=$(printf '%s' "$resp" | extract_upid)
if [[ -n "$upid" ]]; then
  wait_for_task "$node" "$upid"
fi

# Convert to template
resp=$(api_post "/nodes/${node}/qemu/${vmid}/template")
upid=$(printf '%s' "$resp" | extract_upid)
if [[ -n "$upid" ]]; then
  wait_for_task "$node" "$upid"
fi

# Evidence packet
"${FABRIC_REPO_ROOT}/ops/images/vm/register/register-evidence.sh" \
  --mode register \
  --image "${CONTRACT_NAME}" \
  --version "${CONTRACT_VERSION}" \
  --contract "${contract}" \
  --env "${env_name}" \
  --storage "${storage}" \
  --vmid "${vmid}" \
  --node "${node}" \
  --name "${template_name}" \
  --qcow2 "${qcow2}" \
  --sha256 "${computed_ref}" \
  --tags "${tags}" \
  --notes "${notes}" \
  --api-host "${api_host}"
