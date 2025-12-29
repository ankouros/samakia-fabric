#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ZONE_NAME="zonedns"
ZONE_TYPE="vlan"
ZONE_BRIDGE="vmbr0"

VNET_NAME="vlandns"
VLAN_TAG="100"

SUBNET_CIDR="10.10.100.0/24"
SUBNET_GATEWAY="10.10.100.1"

usage() {
  cat >&2 <<EOF
Usage:
  proxmox-sdn-ensure-dns-plane.sh

Ensures Proxmox SDN primitives exist for the DNS VLAN plane (idempotent, strict TLS):
  - zone:   ${ZONE_NAME} (type=${ZONE_TYPE}, bridge=${ZONE_BRIDGE})
  - vnet:   ${VNET_NAME} (tag=${VLAN_TAG})
  - subnet: ${SUBNET_CIDR} (gateway=${SUBNET_GATEWAY})

Auth (API token only; values never printed):
  PM_API_URL / TF_VAR_pm_api_url
  PM_API_TOKEN_ID / TF_VAR_pm_api_token_id
  PM_API_TOKEN_SECRET / TF_VAR_pm_api_token_secret

Behavior:
  - Create if missing
  - Validate shape if present
  - Fail loudly on mismatch (no dangerous mutation)

EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

api_url="${PM_API_URL:-${TF_VAR_pm_api_url:-}}"
token_id="${PM_API_TOKEN_ID:-${TF_VAR_pm_api_token_id:-}}"
token_secret="${PM_API_TOKEN_SECRET:-${TF_VAR_pm_api_token_secret:-}}"

if [[ -z "${api_url}" || -z "${token_id}" || -z "${token_secret}" ]]; then
  echo "ERROR: missing Proxmox API token env vars (PM_API_URL/PM_API_TOKEN_ID/PM_API_TOKEN_SECRET or TF_VAR_* equivalents)." >&2
  exit 1
fi

if [[ ! "${api_url}" =~ ^https:// ]]; then
  echo "ERROR: Proxmox API URL must be https:// (strict TLS): ${api_url}" >&2
  exit 1
fi

if [[ "${token_id}" != *"!"* ]]; then
  echo "ERROR: Proxmox token id must include '!': ${token_id}" >&2
  exit 1
fi

# Enforce strict TLS + token-only constraints (and verify host CA trust).
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/check-proxmox-ca-and-tls.sh" >/dev/null

python3 - <<'PY' \
  "${api_url}" "${token_id}" "${token_secret}" \
  "${ZONE_NAME}" "${ZONE_TYPE}" "${ZONE_BRIDGE}" \
  "${VNET_NAME}" "${VLAN_TAG}" \
  "${SUBNET_CIDR}" "${SUBNET_GATEWAY}"
import json
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

api_url, token_id, token_secret, zone_name, zone_type, zone_bridge, vnet_name, vlan_tag, subnet_cidr, subnet_gw = sys.argv[1:]

base = api_url.rstrip("/")
ctx = ssl.create_default_context()
auth = {"Authorization": f"PVEAPIToken={token_id}={token_secret}"}

def _req(method: str, path: str, data: dict | None = None) -> dict:
    url = f"{base}{path}"
    headers = dict(auth)
    body = None
    if data is not None:
        body = urllib.parse.urlencode(data).encode("utf-8")
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15, context=ctx) as resp:
            raw = resp.read().decode("utf-8")
        parsed = json.loads(raw) if raw else {}
        if isinstance(parsed, dict) and "data" in parsed:
            return parsed
        return {"data": parsed}
    except urllib.error.HTTPError as e:
        msg = e.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"{method} {path} -> HTTP {e.code}: {msg or str(e)}") from None

def get(path: str) -> list[dict]:
    payload = _req("GET", path)
    data = payload.get("data")
    if data is None:
        return []
    if not isinstance(data, list):
        raise RuntimeError(f"GET {path}: expected list, got {type(data).__name__}")
    return [x for x in data if isinstance(x, dict)]

def post(path: str, data: dict) -> None:
    _req("POST", path, data=data)

def find_by_key(items: list[dict], key: str, value: str) -> dict | None:
    for item in items:
        if str(item.get(key, "")) == value:
            return item
    return None

changes: list[str] = []

# 1) Zone
zones = get("/cluster/sdn/zones")
zone = find_by_key(zones, "zone", zone_name) or find_by_key(zones, "name", zone_name)
if not zone:
    post("/cluster/sdn/zones", {"zone": zone_name, "type": zone_type, "bridge": zone_bridge})
    changes.append(f"created zone={zone_name}")
    zones = get("/cluster/sdn/zones")
    zone = find_by_key(zones, "zone", zone_name) or find_by_key(zones, "name", zone_name)
if not zone:
    raise RuntimeError(f"zone creation failed or not visible: {zone_name}")

actual_type = str(zone.get("type", ""))
actual_bridge = str(zone.get("bridge", ""))
if actual_type and actual_type != zone_type:
    raise RuntimeError(f"zone mismatch: {zone_name} type expected={zone_type} got={actual_type}")
if actual_bridge and actual_bridge != zone_bridge:
    raise RuntimeError(f"zone mismatch: {zone_name} bridge expected={zone_bridge} got={actual_bridge}")

# 2) VNet
vnets = get("/cluster/sdn/vnets")
vnet = find_by_key(vnets, "vnet", vnet_name) or find_by_key(vnets, "name", vnet_name)
if not vnet:
    post("/cluster/sdn/vnets", {"vnet": vnet_name, "zone": zone_name, "tag": vlan_tag})
    changes.append(f"created vnet={vnet_name}")
    vnets = get("/cluster/sdn/vnets")
    vnet = find_by_key(vnets, "vnet", vnet_name) or find_by_key(vnets, "name", vnet_name)
if not vnet:
    raise RuntimeError(f"vnet creation failed or not visible: {vnet_name}")

actual_zone = str(vnet.get("zone", ""))
if actual_zone and actual_zone != zone_name:
    raise RuntimeError(f"vnet mismatch: {vnet_name} zone expected={zone_name} got={actual_zone}")

actual_tag = str(vnet.get("tag", ""))
if actual_tag and actual_tag != vlan_tag:
    raise RuntimeError(f"vnet mismatch: {vnet_name} tag expected={vlan_tag} got={actual_tag}")

# 3) Subnet (vnet-scoped)
subnets: list[dict]
try:
    subnets = get(f"/cluster/sdn/vnets/{vnet_name}/subnets")
except RuntimeError as e:
    # If endpoint errors before vnet exists, it's handled above; otherwise propagate.
    raise

subnet = find_by_key(subnets, "subnet", subnet_cidr)
if not subnet:
    post(f"/cluster/sdn/vnets/{vnet_name}/subnets", {"subnet": subnet_cidr, "gateway": subnet_gw})
    changes.append(f"created subnet={subnet_cidr}")
    subnets = get(f"/cluster/sdn/vnets/{vnet_name}/subnets")
    subnet = find_by_key(subnets, "subnet", subnet_cidr)
if not subnet:
    raise RuntimeError(f"subnet creation failed or not visible: {subnet_cidr}")

actual_gw = str(subnet.get("gateway", ""))
if actual_gw and actual_gw != subnet_gw:
    raise RuntimeError(f"subnet mismatch: {subnet_cidr} gateway expected={subnet_gw} got={actual_gw}")

if changes:
    print("OK: SDN DNS plane ensured (" + ", ".join(changes) + ")")
else:
    print("OK: SDN DNS plane already present (no changes)")
PY
