#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"

# Canonical SDN contracts (MinIO stateful plane)
SDN_ZONE="zminio"
SDN_VNET="vminio"
SDN_VLAN_ID="140"
SDN_SUBNET="10.10.140.0/24"
SDN_GATEWAY_VIP="10.10.140.1"

# Canonical MinIO CT placement (deterministic VMIDs + nodes)
MINIO_1_NODE="proxmox1"
MINIO_1_VMID="3211"
MINIO_1_IP="10.10.140.11/24"

MINIO_2_NODE="proxmox2"
MINIO_2_VMID="3212"
MINIO_2_IP="10.10.140.12/24"

MINIO_3_NODE="proxmox3"
MINIO_3_VMID="3213"
MINIO_3_IP="10.10.140.13/24"

EDGE_1_NODE="proxmox1"
EDGE_1_VMID="3201"

EDGE_2_NODE="proxmox2"
EDGE_2_VMID="3202"

# Canonical VIPs (LAN)
DNS_VIP="192.168.11.100"
MINIO_VIP="192.168.11.101"

# LAN gateway (used for routing semantic checks from edge)
LAN_GW="192.168.11.1"

usage() {
  cat >&2 <<'EOF'
Usage:
  minio-sdn-accept.sh

Read-only MinIO SDN acceptance tests for Samakia Fabric.

Validates (best-effort, non-destructive):
  A) Proxmox SDN primitives exist: zone/vnet/subnet/gateway
  B) MinIO CT network wiring (when CTs exist): vlan-only nodes; dual-homed edges
  C) Gateway semantics (when edges exist and SSH is possible): exactly one VLAN GW VIP holder; NAT readiness
  D) Isolation signals (best-effort): MinIO nodes not reachable from LAN runner; edges SSH reachable from allowlisted runner
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

token_has_sdn_allocate() {
  api_get "/access/permissions" | python3 -c '
import json,sys
payload=json.load(sys.stdin)
data=payload.get("data",{})
perms=data.get("/sdn",{}) or data.get("/",{})
print("1" if int(perms.get("SDN.Allocate",0) or 0)==1 else "0")
'
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
  # prints the field value or empty string
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
        gw=s.get("gateway","")
        print("" if gw is None else str(gw))
        sys.exit(0)
print("")
' "${SDN_SUBNET}"
}

extract_ct_networks() {
  # prints lines: key<TAB>bridge<TAB>ip<TAB>gw
  local code
  code="$(cat <<'PY'
import json
import re
import sys

payload = json.load(sys.stdin)
data = payload.get("data")
if not isinstance(data, dict):
    sys.exit(0)

def parse_net(value: str) -> dict[str, str]:
    out: dict[str, str] = {"bridge": "", "ip": "", "gw": ""}
    for part in str(value).split(","):
        if "=" not in part:
            continue
        key, val = part.split("=", 1)
        out[key.strip()] = val.strip()
    return out

for key, value in sorted(data.items()):
    if not re.match(r"^net\d+$", str(key)):
        continue
    net = parse_net(value)
    print("{}\t{}\t{}\t{}".format(key, net.get("bridge", ""), net.get("ip", ""), net.get("gw", "")))
PY
)"
  python3 -c "${code}"
}

ct_config_or_skip() {
  local node="$1"
  local vmid="$2"
  local label="$3"
  local tmp
  tmp="$(mktemp)"
  if ! api_get "/nodes/${node}/lxc/${vmid}/config" >"${tmp}" 2>/dev/null; then
    rm -f "${tmp}"
    skip "${label}: CT config not found via API (node=${node} vmid=${vmid}); deploy the env first"
    return 1
  fi
  if [[ ! -s "${tmp}" ]] || ! python3 -c 'import json,sys; json.load(open(sys.argv[1], "r", encoding="utf-8"))' "${tmp}" >/dev/null 2>&1; then
    rm -f "${tmp}"
    skip "${label}: CT config unreadable via API (node=${node} vmid=${vmid}); check Proxmox API permissions"
    return 1
  fi
  cat "${tmp}"
  rm -f "${tmp}"
  return 0
}

ssh_run() {
  local host="$1"
  shift
  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new \
    "samakia@${host}" \
    "$@"
}

###############################################################################
# A) Proxmox SDN existence (API-level)
###############################################################################

require_proxmox_api

zones_json="$(get_zone_json)"
if [[ "$(printf '%s' "${zones_json}" | json_has_zone)" != "1" ]]; then
  if [[ "$(token_has_sdn_allocate)" != "1" ]]; then
    fail "SDN zone missing: ${SDN_ZONE} (and token lacks SDN.Allocate; the SDN plane must be pre-created by an operator with SDN.Allocate)"
  fi
  fail "SDN zone missing: ${SDN_ZONE}"
fi

zone_type="$(printf '%s' "${zones_json}" | json_zone_field type)"
if [[ -n "${zone_type}" && "${zone_type}" != "vlan" ]]; then
  fail "SDN zone ${SDN_ZONE} type mismatch: expected=vlan got=${zone_type}"
fi
ok "SDN zone exists: ${SDN_ZONE}"

vnets_json="$(get_vnet_json)"
if [[ "$(printf '%s' "${vnets_json}" | json_has_vnet)" != "1" ]]; then
  fail "SDN vnet missing: ${SDN_VNET}"
fi
vnet_zone="$(printf '%s' "${vnets_json}" | json_vnet_field zone)"
if [[ -n "${vnet_zone}" && "${vnet_zone}" != "${SDN_ZONE}" ]]; then
  fail "SDN vnet ${SDN_VNET} zone mismatch: expected=${SDN_ZONE} got=${vnet_zone}"
fi
vnet_tag="$(printf '%s' "${vnets_json}" | json_vnet_field tag)"
if [[ -n "${vnet_tag}" && "${vnet_tag}" != "${SDN_VLAN_ID}" ]]; then
  fail "SDN vnet ${SDN_VNET} VLAN tag mismatch: expected=${SDN_VLAN_ID} got=${vnet_tag}"
fi
ok "SDN vnet exists: ${SDN_VNET} (vlan=${SDN_VLAN_ID})"

subnets_json="$(get_subnets_json)"
if [[ "$(printf '%s' "${subnets_json}" | json_has_subnet)" != "1" ]]; then
  fail "SDN subnet missing on ${SDN_VNET}: ${SDN_SUBNET}"
fi
gw="$(printf '%s' "${subnets_json}" | json_subnet_gateway)"
if [[ -n "${gw}" && "${gw}" != "${SDN_GATEWAY_VIP}" ]]; then
  fail "SDN subnet gateway mismatch: expected=${SDN_GATEWAY_VIP} got=${gw}"
fi
ok "SDN subnet exists: ${SDN_SUBNET} (gw=${SDN_GATEWAY_VIP})"

###############################################################################
# B) LXC network attachment (best-effort; requires CTs exist)
###############################################################################

check_minio_node() {
  local node="$1"
  local vmid="$2"
  local expected_ip="$3"
  local label="$4"

  cfg="$(ct_config_or_skip "${node}" "${vmid}" "${label}")" || return 0

  nets="$(printf '%s' "${cfg}" | extract_ct_networks || true)"
  if [[ -z "${nets}" ]]; then
    fail "${label}: no net* config found (node=${node} vmid=${vmid})"
  fi

  count="$(printf '%s\n' "${nets}" | wc -l | awk '{print $1}')"
  if [[ "${count}" -ne 1 ]]; then
    fail "${label}: expected exactly 1 interface, got ${count}"
  fi

  bridge="$(printf '%s' "${nets}" | awk -F'\t' '{print $2}')"
  ip="$(printf '%s' "${nets}" | awk -F'\t' '{print $3}')"
  gw="$(printf '%s' "${nets}" | awk -F'\t' '{print $4}')"

  if [[ "${bridge}" != "${SDN_VNET}" ]]; then
    fail "${label}: expected bridge=${SDN_VNET}, got ${bridge}"
  fi
  if [[ "${ip}" != "${expected_ip}" ]]; then
    fail "${label}: expected ip=${expected_ip}, got ${ip:-<empty>}"
  fi
  if [[ "${gw}" != "${SDN_GATEWAY_VIP}" ]]; then
    fail "${label}: expected gw=${SDN_GATEWAY_VIP}, got ${gw:-<empty>}"
  fi
  ok "${label}: vlan-only network OK (${ip} via ${SDN_VNET}, gw=${SDN_GATEWAY_VIP})"
}

check_edge() {
  local node="$1"
  local vmid="$2"
  local label="$3"

  cfg="$(ct_config_or_skip "${node}" "${vmid}" "${label}")" || return 0
  nets="$(printf '%s' "${cfg}" | extract_ct_networks || true)"
  if [[ -z "${nets}" ]]; then
    fail "${label}: no net* config found (node=${node} vmid=${vmid})"
  fi

  # Must have one LAN bridge and one VLAN bridge.
  if ! printf '%s\n' "${nets}" | awk -F'\t' '{print $2}' | grep -qx "vmbr0"; then
    fail "${label}: missing LAN interface (bridge=vmbr0)"
  fi
  if ! printf '%s\n' "${nets}" | awk -F'\t' '{print $2}' | grep -qx "${SDN_VNET}"; then
    fail "${label}: missing VLAN interface (bridge=${SDN_VNET})"
  fi

  # Ensure VIP IPs are not configured as static IPs on any interface.
  if printf '%s\n' "${nets}" | awk -F'\t' '{print $3}' | grep -Eq "^(${DNS_VIP}|${MINIO_VIP})/"; then
    fail "${label}: static IP collision with reserved VIP detected in CT config"
  fi

  ok "${label}: dual-homed (vmbr0 + ${SDN_VNET}); no VIP collisions in CT config"
}

check_minio_node "${MINIO_1_NODE}" "${MINIO_1_VMID}" "${MINIO_1_IP}" "minio-1"
check_minio_node "${MINIO_2_NODE}" "${MINIO_2_VMID}" "${MINIO_2_IP}" "minio-2"
check_minio_node "${MINIO_3_NODE}" "${MINIO_3_VMID}" "${MINIO_3_IP}" "minio-3"
check_edge "${EDGE_1_NODE}" "${EDGE_1_VMID}" "minio-edge-1"
check_edge "${EDGE_2_NODE}" "${EDGE_2_VMID}" "minio-edge-2"

###############################################################################
# C/D) Gateway routing + isolation signals (best-effort via SSH to edges)
###############################################################################

# Resolve edge management IPs from Ansible host_vars (source of truth for ops access).
# Parse YAML without adding dependencies: expect a simple top-level "ansible_host: <ip>".
EDGE1_LAN="$(awk -F': ' '$1=="ansible_host"{print $2; exit}' "${FABRIC_REPO_ROOT}/fabric-core/ansible/host_vars/minio-edge-1.yml" 2>/dev/null || true)"
EDGE2_LAN="$(awk -F': ' '$1=="ansible_host"{print $2; exit}' "${FABRIC_REPO_ROOT}/fabric-core/ansible/host_vars/minio-edge-2.yml" 2>/dev/null || true)"

if [[ -z "${EDGE1_LAN}" || -z "${EDGE2_LAN}" ]]; then
  skip "edge SSH checks: could not resolve edge ansible_host values from host_vars"
else
  # SSH positive access check (runner must be allowlisted by design).
  if ! ssh_run "${EDGE1_LAN}" true >/dev/null 2>&1; then
    skip "edge SSH checks: cannot SSH to ${EDGE1_LAN} as samakia (runner may not be allowlisted or CT not reachable)"
  elif ! ssh_run "${EDGE2_LAN}" true >/dev/null 2>&1; then
    skip "edge SSH checks: cannot SSH to ${EDGE2_LAN} as samakia (runner may not be allowlisted or CT not reachable)"
  else
    ok "SSH to minio-edge mgmt IPs works from runner (allowlist positive check)"

    # Exactly one edge holds VLAN gateway VIP (VRRP).
    holders=0
    active=""
    for h in "${EDGE1_LAN}" "${EDGE2_LAN}"; do
      if ssh_run "${h}" "ip -4 addr show | grep -q \"${SDN_GATEWAY_VIP}/\""; then
        holders=$((holders + 1))
        active="${h}"
      fi
    done
    if [[ "${holders}" -ne 1 ]]; then
      fail "expected exactly one VLAN GW VIP holder for ${SDN_GATEWAY_VIP}; got ${holders}"
    fi
    ok "exactly one edge holds VLAN GW VIP ${SDN_GATEWAY_VIP} (active=${active})"

    ipf="$(ssh_run "${active}" sysctl -n net.ipv4.ip_forward || true)"
    if [[ "${ipf}" != "1" ]]; then
      fail "ip_forward expected 1 on active edge; got ${ipf:-<empty>}"
    fi
    ok "ip_forward=1 on active edge"

    # NAT readiness (best-effort): require a masquerade rule for the VLAN CIDR.
    if ! ssh_run "${active}" "sudo nft list ruleset | grep -F \"${SDN_SUBNET}\" | grep -qi \"masquerade\""; then
      skip "NAT check: could not confirm masquerade rule for ${SDN_SUBNET} via nftables on active edge"
    else
      ok "nftables masquerade rule present for ${SDN_SUBNET} (best-effort)"
    fi

    if ! ssh_run "${active}" "ping -c 1 -W 1 ${LAN_GW} >/dev/null"; then
      skip "LAN reachability: active edge could not reach LAN gateway ${LAN_GW} (best-effort)"
    else
      ok "active edge can reach LAN gateway ${LAN_GW} (best-effort)"
    fi
  fi
fi

# MinIO nodes must not be reachable from LAN runner (best-effort): ping must fail.
for ip in "10.10.140.11" "10.10.140.12" "10.10.140.13"; do
  if ping -c 1 -W 1 "${ip}" >/dev/null 2>&1; then
    fail "isolation violation: MinIO node responded to ICMP from runner (LAN): ${ip}"
  fi
done
ok "MinIO VLAN nodes do not respond to ICMP from runner (best-effort isolation signal)"

###############################################################################
# E) Collision policy (best-effort)
###############################################################################

# Without list permissions, we cannot prove absence cluster-wide; we assert:
# - VIP IPs are not assigned as static IPs on the known MinIO CT configs (above)
# - and that VIP IPs are not present in SDN subnet/gateway definitions.
if [[ "${SDN_GATEWAY_VIP}" == "${DNS_VIP}" || "${SDN_GATEWAY_VIP}" == "${MINIO_VIP}" ]]; then
  fail "collision: SDN gateway VIP collides with reserved LAN VIPs"
fi
ok "no VIP collision signals detected in SDN definitions (best-effort)"

if [[ "${skipped}" -eq 1 ]]; then
  echo "[OK] MinIO SDN acceptance completed with SKIP(s) (environment not fully deployed/reachable in this runner context)."
else
  echo "[OK] MinIO SDN acceptance completed (full coverage)."
fi
