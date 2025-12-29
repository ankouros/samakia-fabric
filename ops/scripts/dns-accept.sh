#!/usr/bin/env bash
set -euo pipefail

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

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

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
# 8) No secret leakage (best-effort local scan)
###############################################################################

if [[ -d "audit" ]]; then
  if rg -n "PVEAPIToken=|PM_API_TOKEN_SECRET=|TF_VAR_pm_api_token_secret=" audit 2>/dev/null | head -n 1 >/dev/null; then
    fail "token-like strings found under audit/ (refusing)"
  fi
fi
pass "No obvious token leakage in audit/ (best-effort scan)"

pass "DNS acceptance suite complete"
