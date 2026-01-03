#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"

# Canonical SDN contracts (DNS plane)
SDN_ZONE="zonedns"
SDN_ZONE_TYPE="vlan"
SDN_ZONE_BRIDGE="vmbr0"
SDN_VNET="vlandns"
SDN_VLAN_ID="100"
SDN_SUBNET="10.10.100.0/24"
SDN_GATEWAY_VIP="10.10.100.1"

usage() {
  cat >&2 <<'USAGE'
Usage:
  dns-sdn-accept.sh

Read-only DNS SDN acceptance tests for Samakia Fabric.
Validates:
  - Proxmox SDN primitives exist: zone/vnet/subnet/gateway
  - Zone type and bridge match canonical values
  - VNet VLAN tag matches canonical VLAN ID

Notes:
  - This script is deterministic and does not mutate Terraform state or Proxmox.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "[FAIL] missing required command: $1" >&2; exit 1; }
}

need curl
need python3

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

ok() { echo "[OK] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

proxmox_api_url="${PM_API_URL:-${TF_VAR_pm_api_url:-}}"
proxmox_token_id="${PM_API_TOKEN_ID:-${TF_VAR_pm_api_token_id:-}}"
proxmox_token_secret="${PM_API_TOKEN_SECRET:-${TF_VAR_pm_api_token_secret:-}}"

require_proxmox_api() {
  if [[ -z "${proxmox_api_url}" || -z "${proxmox_token_id}" || -z "${proxmox_token_secret}" ]]; then
    fail "missing Proxmox API token env vars (PM_API_URL/PM_API_TOKEN_ID/PM_API_TOKEN_SECRET or TF_VAR_* equivalents)"
  fi
  if [[ ! "${proxmox_api_url}" =~ ^https:// ]]; then
    fail "PM_API_URL must be https:// (strict TLS): ${proxmox_api_url}"
  fi
  if [[ "${proxmox_token_id}" != *"!"* ]]; then
    fail "PM_API_TOKEN_ID must include '!' (redacted)"
  fi
  bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/check-proxmox-ca-and-tls.sh" >/dev/null
}

api_get() {
  local path="$1"
  curl -fsS \
    -H "Authorization: PVEAPIToken=${proxmox_token_id}=${proxmox_token_secret}" \
    "${proxmox_api_url%/}${path}"
}

get_zone_json() { api_get "/cluster/sdn/zones"; }
get_vnet_json() { api_get "/cluster/sdn/vnets"; }
get_subnets_json() { api_get "/cluster/sdn/vnets/${SDN_VNET}/subnets"; }

json_has_zone() {
  python3 -c '
import json,sys
payload=json.load(sys.stdin)
name=sys.argv[1]
for z in payload.get("data",[]):
    if str(z.get("zone", ""))==name or str(z.get("name", ""))==name:
        print("1"); sys.exit(0)
print("0")
' "${SDN_ZONE}"
}

json_zone_field() {
  local field="$1"
  python3 -c '
import json,sys
payload=json.load(sys.stdin)
name=sys.argv[1]
field=sys.argv[2]
for z in payload.get("data",[]):
    if str(z.get("zone", ""))==name or str(z.get("name", ""))==name:
        v=z.get(field,"")
        print("" if v is None else str(v))
        sys.exit(0)
print("")
' "${SDN_ZONE}" "${field}"
}

json_has_vnet() {
  python3 -c '
import json,sys
payload=json.load(sys.stdin)
name=sys.argv[1]
for v in payload.get("data",[]):
    if str(v.get("vnet", ""))==name or str(v.get("name", ""))==name:
        print("1"); sys.exit(0)
print("0")
' "${SDN_VNET}"
}

json_vnet_field() {
  local field="$1"
  python3 -c '
import json,sys
payload=json.load(sys.stdin)
name=sys.argv[1]
field=sys.argv[2]
for v in payload.get("data",[]):
    if str(v.get("vnet", ""))==name or str(v.get("name", ""))==name:
        val=v.get(field,"")
        print("" if val is None else str(val))
        sys.exit(0)
print("")
' "${SDN_VNET}" "${field}"
}

json_has_subnet() {
  python3 -c '
import json,sys
payload=json.load(sys.stdin)
subnet=sys.argv[1]
for s in payload.get("data",[]):
    if str(s.get("cidr", ""))==subnet or str(s.get("subnet", ""))==subnet:
        print("1"); sys.exit(0)
print("0")
' "${SDN_SUBNET}"
}

json_subnet_gateway() {
  python3 -c '
import json,sys
payload=json.load(sys.stdin)
subnet=sys.argv[1]
for s in payload.get("data",[]):
    if str(s.get("cidr", ""))==subnet or str(s.get("subnet", ""))==subnet:
        gw=s.get("gateway","")
        print("" if gw is None else str(gw))
        sys.exit(0)
print("")
' "${SDN_SUBNET}"
}

require_proxmox_api

zones_json="$(get_zone_json)"
if [[ "$(printf '%s' "${zones_json}" | json_has_zone)" != "1" ]]; then
  fail "SDN zone missing: ${SDN_ZONE}"
fi
zone_type="$(printf '%s' "${zones_json}" | json_zone_field type)"
zone_bridge="$(printf '%s' "${zones_json}" | json_zone_field bridge)"
if [[ "${zone_type}" != "${SDN_ZONE_TYPE}" ]]; then
  fail "SDN zone type mismatch: expected=${SDN_ZONE_TYPE} got=${zone_type}"
fi
if [[ -n "${SDN_ZONE_BRIDGE}" && "${zone_bridge}" != "${SDN_ZONE_BRIDGE}" ]]; then
  fail "SDN zone bridge mismatch: expected=${SDN_ZONE_BRIDGE} got=${zone_bridge}"
fi
ok "SDN zone OK: ${SDN_ZONE} (type=${zone_type} bridge=${zone_bridge})"

vnet_json="$(get_vnet_json)"
if [[ "$(printf '%s' "${vnet_json}" | json_has_vnet)" != "1" ]]; then
  fail "SDN vnet missing: ${SDN_VNET}"
fi
tag="$(printf '%s' "${vnet_json}" | json_vnet_field tag)"
if [[ "${tag}" != "${SDN_VLAN_ID}" ]]; then
  fail "SDN vnet VLAN tag mismatch: expected=${SDN_VLAN_ID} got=${tag}"
fi
ok "SDN vnet OK: ${SDN_VNET} (tag=${tag})"

subnets_json="$(get_subnets_json)"
if [[ "$(printf '%s' "${subnets_json}" | json_has_subnet)" != "1" ]]; then
  fail "SDN subnet missing on ${SDN_VNET}: ${SDN_SUBNET}"
fi
gw="$(printf '%s' "${subnets_json}" | json_subnet_gateway)"
if [[ "${gw}" != "${SDN_GATEWAY_VIP}" ]]; then
  fail "SDN subnet gateway mismatch: expected=${SDN_GATEWAY_VIP} got=${gw}"
fi
ok "SDN subnet OK: ${SDN_SUBNET} (gw=${SDN_GATEWAY_VIP})"

ok "DNS SDN acceptance PASS"
