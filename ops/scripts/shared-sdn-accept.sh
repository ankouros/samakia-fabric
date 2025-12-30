#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"

# Canonical SDN contracts (Shared services plane)
SDN_ZONE="zshared"
SDN_VNET="vshared"
SDN_VLAN_ID="120"
SDN_SUBNET="10.10.120.0/24"
SDN_GATEWAY_VIP="10.10.120.1"

# Canonical shared CT placement
NTP_1_NODE="proxmox1"
NTP_1_VMID="3301"
NTP_1_LAN_IP="192.168.11.106/24"
NTP_1_VLAN_IP="10.10.120.11/24"

NTP_2_NODE="proxmox2"
NTP_2_VMID="3302"
NTP_2_LAN_IP="192.168.11.107/24"
NTP_2_VLAN_IP="10.10.120.12/24"

VAULT_1_NODE="proxmox3"
VAULT_1_VMID="3303"
VAULT_1_IP="10.10.120.21/24"

VAULT_2_NODE="proxmox1"
VAULT_2_VMID="3304"
VAULT_2_IP="10.10.120.22/24"

OBS_1_NODE="proxmox2"
OBS_1_VMID="3305"
OBS_1_IP="10.10.120.31/24"

# Canonical VIPs (LAN)
DNS_VIP="192.168.11.100"
MINIO_VIP="192.168.11.101"
NTP_VIP="192.168.11.120"
VAULT_VIP="192.168.11.121"
OBS_VIP="192.168.11.122"

LAN_GW="192.168.11.1"

usage() {
  cat >&2 <<'EOF'
Usage:
  shared-sdn-accept.sh

Read-only Shared SDN acceptance tests for Samakia Fabric.

Validates (best-effort, non-destructive):
  A) Proxmox SDN primitives exist: zone/vnet/subnet/gateway
  B) Shared CT network wiring (when CTs exist): VLAN-only nodes; dual-homed NTP/edge nodes
  C) Gateway semantics (when edges exist and SSH is possible): exactly one VLAN GW VIP holder; NAT readiness
  D) Isolation signals (best-effort): VLAN nodes not reachable from LAN runner
  E) Collision signals (best-effort): VIP IPs are not assigned as static CT IPs

Notes:
  - This script is deterministic and does not mutate Terraform state or Proxmox.
  - If the expected CTs are not deployed yet, CT-level checks are reported as [SKIP].
EOF
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
need grep
need awk
need ssh
need ping

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

ok() { echo "[OK] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }
skip() { echo "[SKIP] $*"; skipped=1; }

skipped=0

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
    fail "PM_API_TOKEN_ID must include '!': (redacted)"
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
get_ct_config_json() {
  local node="$1"
  local vmid="$2"
  api_get "/nodes/${node}/lxc/${vmid}/config"
}

json_has_zone() {
  python3 -c '
import json,sys
payload=json.load(sys.stdin)
data=payload.get("data",[])
name=sys.argv[1]
for z in data:
    if str(z.get("zone",""))==name or str(z.get("name",""))==name:
        print("1"); sys.exit(0)
print("0")
' "${SDN_ZONE}"
}

json_zone_field() {
  local field="$1"
  python3 -c '
import json,sys
payload=json.load(sys.stdin)
data=payload.get("data",[])
name=sys.argv[1]
field=sys.argv[2]
for z in data:
    if str(z.get("zone",""))==name or str(z.get("name",""))==name:
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
data=payload.get("data",[])
name=sys.argv[1]
for v in data:
    if str(v.get("vnet",""))==name or str(v.get("name",""))==name:
        print("1"); sys.exit(0)
print("0")
' "${SDN_VNET}"
}

json_vnet_field() {
  local field="$1"
  python3 -c '
import json,sys
payload=json.load(sys.stdin)
data=payload.get("data",[])
name=sys.argv[1]
field=sys.argv[2]
for v in data:
    if str(v.get("vnet",""))==name or str(v.get("name",""))==name:
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
data=payload.get("data",[])
subnet=sys.argv[1]
for s in data:
    if str(s.get("cidr",""))==subnet or str(s.get("subnet",""))==subnet:
        print("1"); sys.exit(0)
print("0")
' "${SDN_SUBNET}"
}

json_subnet_gateway() {
  python3 -c '
import json,sys
payload=json.load(sys.stdin)
data=payload.get("data",[])
subnet=sys.argv[1]
for s in data:
    if str(s.get("cidr",""))==subnet or str(s.get("subnet",""))==subnet:
        print("" if s.get("gateway") is None else str(s.get("gateway")))
        sys.exit(0)
print("")
' "${SDN_SUBNET}"
}

ct_config_or_skip() {
  local node="$1"
  local vmid="$2"
  local payload
  if ! payload="$(get_ct_config_json "$node" "$vmid" 2>/dev/null)"; then
    skip "CT config not found for ${node}/lxc/${vmid}"
    return 1
  fi
  if ! echo "${payload}" | python3 -c 'import json,sys; json.load(sys.stdin)'; then
    skip "CT config invalid JSON for ${node}/lxc/${vmid}"
    return 1
  fi
  printf '%s' "${payload}"
}

extract_ct_networks() {
  python3 - <<'PY'
import json,sys
payload=json.load(sys.stdin)
data=payload.get("data",{})
for key, val in data.items():
    if not key.startswith("net"):
        continue
    print(f"{key}\t{val}")
PY
}

check_net_contains() {
  local line="$1" field="$2" expect="$3"
  echo "$line" | grep -q "${field}=${expect}"
}

ssh_run() {
  local host="$1"
  shift
  ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "samakia@${host}" "$@"
}

###############################################################################
# A) SDN primitives exist
###############################################################################

require_proxmox_api

zone_json="$(get_zone_json)"
if [[ "$(echo "${zone_json}" | json_has_zone)" != "1" ]]; then
  fail "SDN zone missing: ${SDN_ZONE}"
fi
zone_type="$(echo "${zone_json}" | json_zone_field type)"
zone_bridge="$(echo "${zone_json}" | json_zone_field bridge)"
if [[ -n "${zone_type}" && "${zone_type}" != "vlan" ]]; then
  fail "SDN zone type mismatch: expected vlan got ${zone_type}"
fi
if [[ -n "${zone_bridge}" && "${zone_bridge}" != "vmbr0" ]]; then
  fail "SDN zone bridge mismatch: expected vmbr0 got ${zone_bridge}"
fi
ok "SDN zone OK: ${SDN_ZONE} (type=${zone_type:-vlan} bridge=${zone_bridge:-vmbr0})"

vnet_json="$(get_vnet_json)"
if [[ "$(echo "${vnet_json}" | json_has_vnet)" != "1" ]]; then
  fail "SDN vnet missing: ${SDN_VNET}"
fi
vnet_tag="$(echo "${vnet_json}" | json_vnet_field tag)"
if [[ -n "${vnet_tag}" && "${vnet_tag}" != "${SDN_VLAN_ID}" ]]; then
  fail "SDN vnet tag mismatch: expected ${SDN_VLAN_ID} got ${vnet_tag}"
fi
ok "SDN vnet OK: ${SDN_VNET} (tag=${vnet_tag:-${SDN_VLAN_ID}})"

subnet_json="$(get_subnets_json)"
if [[ "$(echo "${subnet_json}" | json_has_subnet)" != "1" ]]; then
  fail "SDN subnet missing: ${SDN_SUBNET}"
fi
subnet_gw="$(echo "${subnet_json}" | json_subnet_gateway)"
if [[ -n "${subnet_gw}" && "${subnet_gw}" != "${SDN_GATEWAY_VIP}" ]]; then
  fail "SDN subnet gateway mismatch: expected ${SDN_GATEWAY_VIP} got ${subnet_gw}"
fi
ok "SDN subnet OK: ${SDN_SUBNET} (gw=${subnet_gw:-${SDN_GATEWAY_VIP}})"

###############################################################################
# B) CT wiring
###############################################################################

check_vlan_only_node() {
  local node="$1" vmid="$2" expect_ip="$3"
  local payload
  if ! payload="$(ct_config_or_skip "$node" "$vmid")"; then return 0; fi
  local nets
  nets="$(echo "${payload}" | extract_ct_networks)"
  if [[ -z "${nets}" ]]; then
    skip "no network config for ${node}/lxc/${vmid}"
    return 0
  fi
  local count
  count="$(echo "${nets}" | wc -l | tr -d ' ')"
  if [[ "${count}" != "1" ]]; then
    fail "${node}/lxc/${vmid} expected VLAN-only (1 iface) but has ${count}"
  fi
  local line
  line="$(echo "${nets}" | head -n1)"
  check_net_contains "${line}" "bridge" "${SDN_VNET}" || fail "${node}/lxc/${vmid} bridge mismatch (expected ${SDN_VNET})"
  check_net_contains "${line}" "ip" "${expect_ip}" || fail "${node}/lxc/${vmid} ip mismatch (expected ${expect_ip})"
  check_net_contains "${line}" "gw" "${SDN_GATEWAY_VIP}" || fail "${node}/lxc/${vmid} gw mismatch (expected ${SDN_GATEWAY_VIP})"
}

check_dual_homed_edge() {
  local node="$1" vmid="$2" expect_lan="$3" expect_vlan="$4"
  local payload
  if ! payload="$(ct_config_or_skip "$node" "$vmid")"; then return 0; fi
  local nets
  nets="$(echo "${payload}" | extract_ct_networks)"
  if [[ -z "${nets}" ]]; then
    skip "no network config for ${node}/lxc/${vmid}"
    return 0
  fi
  local count
  count="$(echo "${nets}" | wc -l | tr -d ' ')"
  if [[ "${count}" -lt 2 ]]; then
    fail "${node}/lxc/${vmid} expected dual-homed (>=2 ifaces) but has ${count}"
  fi
  local lan_ok=0 vlan_ok=0
  while read -r line; do
    if echo "${line}" | grep -q "bridge=vmbr0"; then
      check_net_contains "${line}" "ip" "${expect_lan}" || true
      lan_ok=1
    fi
    if echo "${line}" | grep -q "bridge=${SDN_VNET}"; then
      check_net_contains "${line}" "ip" "${expect_vlan}" || true
      vlan_ok=1
    fi
  done <<< "${nets}"
  if [[ "${lan_ok}" -ne 1 || "${vlan_ok}" -ne 1 ]]; then
    fail "${node}/lxc/${vmid} missing expected LAN/VLAN interfaces"
  fi
}

check_dual_homed_edge "${NTP_1_NODE}" "${NTP_1_VMID}" "${NTP_1_LAN_IP}" "${NTP_1_VLAN_IP}" && ok "ntp-1: dual-homed OK"
check_dual_homed_edge "${NTP_2_NODE}" "${NTP_2_VMID}" "${NTP_2_LAN_IP}" "${NTP_2_VLAN_IP}" && ok "ntp-2: dual-homed OK"
check_vlan_only_node "${VAULT_1_NODE}" "${VAULT_1_VMID}" "${VAULT_1_IP}" && ok "vault-1: vlan-only OK"
check_vlan_only_node "${VAULT_2_NODE}" "${VAULT_2_VMID}" "${VAULT_2_IP}" && ok "vault-2: vlan-only OK"
check_vlan_only_node "${OBS_1_NODE}" "${OBS_1_VMID}" "${OBS_1_IP}" && ok "obs-1: vlan-only OK"

###############################################################################
# C) Gateway semantics (best-effort)
###############################################################################

edge1_lan="192.168.11.106"
edge2_lan="192.168.11.107"

if ssh_run "${edge1_lan}" true >/dev/null 2>&1 && ssh_run "${edge2_lan}" true >/dev/null 2>&1; then
  ok "SSH to shared edge mgmt IPs works from runner (allowlist positive check)"

  vip_holders=0
  active_edge=""
  for host in "${edge1_lan}" "${edge2_lan}"; do
    if ssh_run "${host}" "ip -4 addr show | grep -q '${SDN_GATEWAY_VIP}/'"; then
      vip_holders=$((vip_holders + 1))
      active_edge="${host}"
    fi
  done
  if [[ "${vip_holders}" -ne 1 ]]; then
    fail "expected exactly one edge holds VLAN GW VIP ${SDN_GATEWAY_VIP}; got ${vip_holders}"
  fi
  ok "exactly one edge holds VLAN GW VIP ${SDN_GATEWAY_VIP} (active=${active_edge})"

  ssh_run "${active_edge}" "sysctl -n net.ipv4.ip_forward" | grep -q "^1$" || fail "ip_forward=1 not set on active edge"
  ok "ip_forward=1 on active edge"

  if ! ssh_run "${active_edge}" "sudo -n true" >/dev/null 2>&1; then
    fail "sudo is required for nftables inspection on ${active_edge} (read-only); allow passwordless sudo for the operator"
  fi

  ssh_run "${active_edge}" "sudo -n nft list ruleset | grep -q 'masquerade'" || fail "nftables masquerade rule missing on active edge"
  ok "nftables masquerade rule present (best-effort)"

  ssh_run "${active_edge}" "ping -c1 -W1 ${LAN_GW} >/dev/null" || fail "active edge cannot reach LAN gateway ${LAN_GW}"
  ok "active edge can reach LAN gateway ${LAN_GW}"
else
  skip "edge SSH not reachable from runner; skipping gateway/NAT checks"
fi

###############################################################################
# D) Isolation signals (best-effort)
###############################################################################

for ip in "10.10.120.21" "10.10.120.22" "10.10.120.31"; do
  if ping -c1 -W1 "${ip}" >/dev/null 2>&1; then
    fail "VLAN node responded to ICMP from runner (expected isolation): ${ip}"
  fi
done
ok "VLAN nodes do not respond to ICMP from runner (best-effort isolation signal)"

###############################################################################
# E) Collision signals (best-effort)
###############################################################################

for ip in "${DNS_VIP}" "${MINIO_VIP}" "${NTP_VIP}" "${VAULT_VIP}" "${OBS_VIP}"; do
  if [[ "${NTP_1_LAN_IP}" == "${ip}" || "${NTP_2_LAN_IP}" == "${ip}" ]]; then
    fail "VIP collision: ${ip} assigned as static LAN IP"
  fi
done
ok "no VIP collision signals detected (best-effort)"

if [[ "${skipped}" -eq 1 ]]; then
  echo "[WARN] Some checks were skipped due to missing CTs or unreachable edges."
fi

ok "Shared SDN acceptance completed"
