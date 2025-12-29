#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

DNS_VIP="192.168.11.100"
DNS_ZONE="infra.samakia.net"

EDGE1_LAN="192.168.11.103"
EDGE2_LAN="192.168.11.102"

AUTH1_VLAN="10.10.100.21"
AUTH2_VLAN="10.10.100.22"

VLAN_GW_VIP="10.10.100.1"
VLAN_CIDR="10.10.100.0/24"

usage() {
  cat >&2 <<'EOF'
Usage:
  dns-accept.sh

Non-interactive DNS acceptance tests for Samakia Fabric.
Validates:
  - DNS VIP answers for infra.samakia.net (SOA + required A records)
  - Recursion via VIP (example.com)
  - keepalived HA readiness (service on both edges; exactly one VIP holder)
  - VLAN gateway VIP present on active edge
  - NAT readiness (ip_forward=1 + nft masquerade rule)
  - PowerDNS replication sanity (query dns-auth-2 from inside VLAN via edge)
  - Ansible idempotency for dns.yml (changed=0)
  - No obvious token leakage in local logs (best-effort)

EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "FAIL: missing required command: $1" >&2; exit 1; }
}

need dig
need ssh
need awk
need grep
need sed
need python3

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

proxmox_api_url="${PM_API_URL:-${TF_VAR_pm_api_url:-}}"
proxmox_token_id="${PM_API_TOKEN_ID:-${TF_VAR_pm_api_token_id:-}}"
proxmox_token_secret="${PM_API_TOKEN_SECRET:-${TF_VAR_pm_api_token_secret:-}}"

require_proxmox_api() {
  if [[ -z "${proxmox_api_url}" || -z "${proxmox_token_id}" || -z "${proxmox_token_secret}" ]]; then
    fail "missing Proxmox API token env vars (PM_API_URL/PM_API_TOKEN_ID/PM_API_TOKEN_SECRET or TF_VAR_* equivalents); required for tag verification"
  fi
  if [[ ! "${proxmox_api_url}" =~ ^https:// ]]; then
    fail "PM_API_URL must be https:// (strict TLS): ${proxmox_api_url}"
  fi
  if [[ "${proxmox_token_id}" != *"!"* ]]; then
    fail "PM_API_TOKEN_ID must include '!': ${proxmox_token_id}"
  fi
  bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/check-proxmox-ca-and-tls.sh" >/dev/null
}

get_lxc_tags() {
  local node="$1"
  local vmid="$2"
  PROXMOX_TOKEN_ID="${proxmox_token_id}" PROXMOX_TOKEN_SECRET="${proxmox_token_secret}" \
    python3 - "${proxmox_api_url}" "${node}" "${vmid}" <<'PY'
import json
import os
import ssl
import sys
import urllib.request

api_url, node, vmid = sys.argv[1:]
token_id = os.environ.get("PROXMOX_TOKEN_ID", "")
token_secret = os.environ.get("PROXMOX_TOKEN_SECRET", "")

ctx = ssl.create_default_context()
headers = {"Authorization": f"PVEAPIToken={token_id}={token_secret}"}
url = f"{api_url.rstrip('/')}/nodes/{node}/lxc/{vmid}/config"
req = urllib.request.Request(url, headers=headers, method="GET")

with urllib.request.urlopen(req, timeout=15, context=ctx) as resp:
    raw = resp.read().decode("utf-8")

payload = json.loads(raw) if raw else {}
data = payload.get("data") if isinstance(payload, dict) else None
if not isinstance(data, dict):
    print("")
else:
    print(str(data.get("tags", "")).strip())
PY
}

assert_tag() {
  local node="$1"
  local vmid="$2"
  local expected_plane="$3"
  local expected_env="$4"
  local expected_role="$5"

  local tags
  tags="$(get_lxc_tags "${node}" "${vmid}")"
  if [[ -z "${tags}" ]]; then
    fail "missing Proxmox tags for CT ${node}/${vmid}"
  fi

  if echo "${tags}" | grep -q ","; then
    fail "CT ${node}/${vmid} tags contain ',' (expected ';' separated tags): ${tags}"
  fi

  if ! echo "${tags}" | grep -Eq '(^|;)golden-v[0-9]+(;|$)'; then
    fail "CT ${node}/${vmid} tags missing golden-vN: ${tags}"
  fi
  if ! echo "${tags}" | grep -Eq "(^|;)plane-${expected_plane}(;|$)"; then
    fail "CT ${node}/${vmid} tags missing plane-${expected_plane}: ${tags}"
  fi
  if ! echo "${tags}" | grep -Eq "(^|;)env-${expected_env}(;|$)"; then
    fail "CT ${node}/${vmid} tags missing env-${expected_env}: ${tags}"
  fi
  if ! echo "${tags}" | grep -Eq "(^|;)role-${expected_role}(;|$)"; then
    fail "CT ${node}/${vmid} tags missing role-${expected_role}: ${tags}"
  fi
}

dig_a() {
  local server="$1"
  local name="$2"
  dig +"time=2" +"tries=3" "@${server}" "${name}" A +short | tr -d '\r'
}

dig_soa() {
  local server="$1"
  local name="$2"
  dig +"time=2" +"tries=3" "@${server}" "${name}" SOA +short | tr -d '\r'
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
# 1) DNS VIP reachable
###############################################################################

soa="$(dig_soa "${DNS_VIP}" "${DNS_ZONE}")"
if [[ -z "${soa}" ]]; then
  fail "DNS VIP did not answer SOA for ${DNS_ZONE} via ${DNS_VIP}"
fi
pass "DNS VIP answers SOA for ${DNS_ZONE}"

###############################################################################
# 2) Authoritative correctness via VIP
###############################################################################

auth1_ip="$(dig_a "${DNS_VIP}" "dns-auth-1.${DNS_ZONE}")"
if [[ "${auth1_ip}" != "${AUTH1_VLAN}" ]]; then
  fail "VIP authoritative mismatch: dns-auth-1.${DNS_ZONE} expected ${AUTH1_VLAN} got ${auth1_ip:-<empty>}"
fi
pass "VIP returns dns-auth-1.${DNS_ZONE} A=${AUTH1_VLAN}"

vip_a="$(dig_a "${DNS_VIP}" "dns.${DNS_ZONE}")"
if [[ "${vip_a}" != "${DNS_VIP}" ]]; then
  fail "VIP authoritative mismatch: dns.${DNS_ZONE} expected ${DNS_VIP} got ${vip_a:-<empty>}"
fi
pass "VIP returns dns.${DNS_ZONE} A=${DNS_VIP}"

###############################################################################
# 3) Recursion
###############################################################################

rec="$(dig_a "${DNS_VIP}" "example.com" | head -n 1)"
if [[ -z "${rec}" ]]; then
  fail "Recursion failed via VIP (${DNS_VIP}) for example.com"
fi
pass "Recursion works via VIP (example.com A present)"

###############################################################################
# 4) HA readiness: keepalived active on both edges; exactly one holds VIP
###############################################################################

for host in "${EDGE1_LAN}" "${EDGE2_LAN}"; do
  if ! ssh_run "${host}" systemctl is-active --quiet keepalived; then
    fail "keepalived is not active on ${host}"
  fi
done
pass "keepalived active on both dns-edge nodes"

vip_holders=0
active_host=""
for host in "${EDGE1_LAN}" "${EDGE2_LAN}"; do
  if ssh_run "${host}" "ip -4 addr show | grep -q \"${DNS_VIP}/\""; then
    vip_holders=$((vip_holders+1))
    active_host="${host}"
  fi
done

if [[ "${vip_holders}" -ne 1 ]]; then
  fail "Expected exactly one VIP holder for ${DNS_VIP}; got ${vip_holders}"
fi
pass "Exactly one dns-edge holds ${DNS_VIP} (active=${active_host})"

if ! ssh_run "${active_host}" "ip -4 addr show | grep -q \"${VLAN_GW_VIP}/\""; then
  fail "Active dns-edge does not hold VLAN GW VIP ${VLAN_GW_VIP}"
fi
pass "Active dns-edge holds VLAN GW VIP ${VLAN_GW_VIP}"

###############################################################################
# 5) NAT readiness (best-effort)
###############################################################################

ipf="$(ssh_run "${active_host}" sysctl -n net.ipv4.ip_forward || true)"
if [[ "${ipf}" != "1" ]]; then
  fail "net.ipv4.ip_forward expected 1 on active dns-edge; got ${ipf:-<empty>}"
fi
pass "ip_forward=1 on active dns-edge"

if ! ssh_run "${active_host}" "nft list ruleset | grep -q \"masquerade\""; then
  fail "nftables masquerade rule missing on active dns-edge"
fi
if ! ssh_run "${active_host}" "nft list ruleset | grep -q \"${VLAN_CIDR}\""; then
  fail "nftables does not reference ${VLAN_CIDR} on active dns-edge"
fi
pass "nftables NAT masquerade configured for ${VLAN_CIDR}"

###############################################################################
# 6) PowerDNS replication sanity (query slave directly from inside VLAN via edge)
###############################################################################

slave_ans="$(ssh_run "${active_host}" "dig +time=2 +tries=3 @${AUTH2_VLAN} dns.${DNS_ZONE} A +short" | head -n 1 | tr -d '\r')"
if [[ "${slave_ans}" != "${DNS_VIP}" ]]; then
  fail "dns-auth-2 did not answer expected record (dns.${DNS_ZONE}): expected ${DNS_VIP} got ${slave_ans:-<empty>}"
fi
pass "dns-auth-2 answers infra zone records (queried from edge)"

###############################################################################
# 7) Idempotency (re-run dns.yml; expect changed=0)
###############################################################################

if command -v ansible-playbook >/dev/null 2>&1; then
  out="$(ANSIBLE_CONFIG=fabric-core/ansible/ansible.cfg FABRIC_TERRAFORM_ENV=samakia-dns ansible-playbook -i fabric-core/ansible/inventory/terraform.py fabric-core/ansible/playbooks/dns.yml -u samakia 2>&1 || true)"
  if echo "${out}" | grep -Eq 'changed=[1-9]'; then
    echo "${out}" >&2
    fail "dns.yml is not idempotent (changed>0 on re-run)"
  fi
  if echo "${out}" | grep -Eq 'failed=[1-9]|unreachable=[1-9]'; then
    echo "${out}" >&2
    fail "dns.yml re-run had failures/unreachable"
  fi
pass "dns.yml idempotency (changed=0)"
else
  echo "WARN: ansible-playbook not found; skipping idempotency check" >&2
fi

###############################################################################
# 8) Proxmox UI tags (golden=image version; plane/env/role)
###############################################################################

require_proxmox_api

assert_tag "proxmox1" "3101" "dns" "infra" "edge"
assert_tag "proxmox2" "3102" "dns" "infra" "edge"
assert_tag "proxmox3" "3111" "dns" "infra" "auth"
assert_tag "proxmox2" "3112" "dns" "infra" "auth"
pass "Proxmox tags present and match schema (golden/plane/env/role)"

###############################################################################
# 9) No secret leakage (best-effort local scan)
###############################################################################

if [[ -d "audit" ]]; then
  if rg -n "PVEAPIToken=|PM_API_TOKEN_SECRET=|TF_VAR_pm_api_token_secret=" audit 2>/dev/null | head -n 1 >/dev/null; then
    fail "token-like strings found under audit/ (refusing)"
  fi
fi
pass "No obvious token leakage in audit/ (best-effort scan)"

pass "DNS acceptance suite complete"
