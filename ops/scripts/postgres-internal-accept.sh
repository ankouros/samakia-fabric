#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"
ENV_CANONICAL="samakia-shared"

DNS_VIP="192.168.11.100"
DNS_PRIMARY="db.internal.shared"
DNS_ALIAS="db.canary.internal"

HAPROXY_NODES=("10.10.120.13" "10.10.120.14")
PATRONI_NODES=("10.10.120.23" "10.10.120.24" "10.10.120.25")
PATRONI_PORT="8008"
POSTGRES_PORT="5432"
POSTGRES_VIP="10.10.120.2"

EDGE_JUMP=("192.168.11.106" "192.168.11.107")

CA_FILE_DEFAULT="${HOME}/.config/samakia-fabric/pki/postgres-internal-ca.crt"
CA_FILE="${POSTGRES_INTERNAL_CA_FILE:-${CA_FILE_DEFAULT}}"

usage() {
  cat >&2 <<'EOT'
Usage:
  postgres-internal-accept.sh

Acceptance checks for internal Postgres (Patroni + HAProxy + VIP).
EOT
}

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "FAIL: missing required command: $1" >&2; exit 1; }
}

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

need dig
need ssh
need python3
need psql

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

if [[ -z "${ENV:-}" ]]; then
  fail "ENV is required (set ENV=${ENV_CANONICAL})"
fi
if [[ "${ENV}" != "${ENV_CANONICAL}" ]]; then
  fail "refusing to run: ENV=${ENV} (expected ENV=${ENV_CANONICAL})"
fi

# 1) Doctor checks
bash "${FABRIC_REPO_ROOT}/ops/scripts/postgres-internal-doctor.sh"

# 2) Proxmox API checks (status + tags)
proxmox_api_url="${PM_API_URL:-${TF_VAR_pm_api_url:-}}"
proxmox_token_id="${PM_API_TOKEN_ID:-${TF_VAR_pm_api_token_id:-}}"
proxmox_token_secret="${PM_API_TOKEN_SECRET:-${TF_VAR_pm_api_token_secret:-}}"

if [[ -z "${proxmox_api_url}" || -z "${proxmox_token_id}" || -z "${proxmox_token_secret}" ]]; then
  fail "missing Proxmox API token env vars (PM_API_URL/PM_API_TOKEN_ID/PM_API_TOKEN_SECRET or TF_VAR_* equivalents)"
fi
if [[ ! "${proxmox_api_url}" =~ ^https:// ]]; then
  fail "PM_API_URL must be https:// (strict TLS): ${proxmox_api_url}"
fi
if [[ "${proxmox_token_id}" != *"!"* ]]; then
  fail "PM_API_TOKEN_ID must include '!': ${proxmox_token_id}"
fi
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/check-proxmox-ca-and-tls.sh" >/dev/null

python3 - "${FABRIC_REPO_ROOT}" "${proxmox_api_url}" "${proxmox_token_id}" "${proxmox_token_secret}" <<'PY'
import json
import os
import ssl
import sys
import urllib.request
from pathlib import Path

repo_root, api_url, token_id, token_secret = sys.argv[1:]
api_url = api_url.rstrip("/")

required = {
    "pg_internal_1": {"role": "postgres"},
    "pg_internal_2": {"role": "postgres"},
    "pg_internal_3": {"role": "postgres"},
    "haproxy_pg_1": {"role": "pg-haproxy"},
    "haproxy_pg_2": {"role": "pg-haproxy"},
}

output_path = Path(repo_root) / "fabric-core" / "terraform" / "envs" / "samakia-shared" / "terraform-output.json"
if not output_path.exists():
    raise SystemExit(f"FAIL: missing terraform output file: {output_path}")

payload = json.loads(output_path.read_text())
inv = payload.get("lxc_inventory", {}).get("value", {})

missing = [name for name in required if name not in inv]
if missing:
    raise SystemExit(f"FAIL: terraform output missing hosts: {', '.join(missing)}")

ctx = ssl.create_default_context()
headers = {"Authorization": f"PVEAPIToken={token_id}={token_secret}"}

def req(path: str):
    url = f"{api_url}{path}"
    request = urllib.request.Request(url, headers=headers, method="GET")
    with urllib.request.urlopen(request, timeout=15, context=ctx) as resp:
        raw = resp.read().decode("utf-8")
    payload = json.loads(raw) if raw else {}
    if isinstance(payload, dict) and "data" in payload:
        return payload["data"]
    return payload

for name, meta in required.items():
    host = inv[name]
    node = host["node"]
    vmid = host["vmid"]
    status = req(f"/nodes/{node}/lxc/{vmid}/status/current").get("status")
    if status != "running":
        raise SystemExit(f"FAIL: {name} is not running ({status})")

    tags = str(req(f"/nodes/{node}/lxc/{vmid}/config").get("tags", ""))
    if "golden-v" not in tags:
        raise SystemExit(f"FAIL: {name} missing golden-v tag")
    if "plane-shared" not in tags:
        raise SystemExit(f"FAIL: {name} missing plane-shared tag")
    if "env-infra" not in tags:
        raise SystemExit(f"FAIL: {name} missing env-infra tag")
    if f"role-{meta['role']}" not in tags:
        raise SystemExit(f"FAIL: {name} missing role-{meta['role']} tag")

print("PASS: Proxmox status + tags OK")
PY

# 3) VIP ownership (exactly one holder)
ssh_opts=(
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o StrictHostKeyChecking=accept-new
  -o PasswordAuthentication=no
  -o LogLevel=ERROR
)

jump_host=""
for ip in "${EDGE_JUMP[@]}"; do
  if ssh "${ssh_opts[@]}" "samakia@${ip}" true >/dev/null 2>&1; then
    jump_host="samakia@${ip}"
    break
  fi
done
if [[ -z "${jump_host}" ]]; then
  fail "cannot reach shared edges for ProxyJump (192.168.11.106/107)"
fi

vip_holders=0
for host in "${HAPROXY_NODES[@]}"; do
  if ssh "${ssh_opts[@]}" -J "${jump_host}" "samakia@${host}" "ip -4 addr show | grep -q '${POSTGRES_VIP}/'"; then
    vip_holders=$((vip_holders+1))
  fi
  ssh "${ssh_opts[@]}" -J "${jump_host}" "samakia@${host}" "sudo -n systemctl is-active --quiet keepalived" || fail "keepalived not active on ${host}"
  ssh "${ssh_opts[@]}" -J "${jump_host}" "samakia@${host}" "sudo -n systemctl is-active --quiet haproxy" || fail "haproxy not active on ${host}"
  ssh "${ssh_opts[@]}" -J "${jump_host}" "samakia@${host}" "sudo -n systemctl is-active --quiet nftables" || fail "nftables not active on ${host}"
  pass "HAProxy services active on ${host}"
done
if [[ "${vip_holders}" -ne 1 ]]; then
  fail "expected exactly one VIP holder for ${POSTGRES_VIP}; got ${vip_holders}"
fi
pass "Exactly one VIP holder present for ${POSTGRES_VIP}"

# 4) Patroni + etcd services
for host in "${PATRONI_NODES[@]}"; do
  ssh "${ssh_opts[@]}" -J "${jump_host}" "samakia@${host}" "sudo -n systemctl is-active --quiet patroni" || fail "patroni not active on ${host}"
  ssh "${ssh_opts[@]}" -J "${jump_host}" "samakia@${host}" "sudo -n systemctl is-active --quiet etcd" || fail "etcd not active on ${host}"
  pass "Patroni + etcd active on ${host}"
done

# 5) HAProxy routes to primary (psql on leader)
if [[ ! -f "${CA_FILE}" ]]; then
  fail "Postgres CA file missing: ${CA_FILE}"
fi

pg_user="${POSTGRES_INTERNAL_ADMIN_USER:-postgres}"
pg_pass="${POSTGRES_INTERNAL_ADMIN_PASSWORD:-}"
if [[ -z "${pg_pass}" ]]; then
  fail "POSTGRES_INTERNAL_ADMIN_PASSWORD is required for leader check"
fi

leader_ip="$(ssh "${ssh_opts[@]}" -J "${jump_host}" "samakia@${PATRONI_NODES[0]}" \
  "python3 - '${PATRONI_NODES[*]}' '${PATRONI_PORT}'" <<'PY'
import json
import sys
import urllib.request

nodes = sys.argv[1].split()
port = int(sys.argv[2])
leader = ""
for ip in nodes:
    url = f"http://{ip}:{port}/patroni"
    with urllib.request.urlopen(url, timeout=5) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    role = str(payload.get("role") or "").lower()
    if role in {"leader", "master", "primary"}:
        leader = ip
        break
if not leader:
    raise SystemExit("no leader found")
print(leader)
PY
)"
if [[ -z "${leader_ip}" ]]; then
  fail "unable to determine Patroni leader IP"
fi

printf '%s' "${pg_pass}" | \
  ssh "${ssh_opts[@]}" -J "${jump_host}" "samakia@${leader_ip}" \
  "read -r pg_pass; PGPASSWORD=\"${pg_pass}\" psql \
  \"host=${leader_ip} port=${POSTGRES_PORT} dbname=postgres user=${pg_user}\" \
  -t -A -v ON_ERROR_STOP=1 -c \"select pg_is_in_recovery();\";" \
  | grep -qx 'f' || fail "Patroni leader did not report primary state"

leader_slot=0
for idx in "${!PATRONI_NODES[@]}"; do
  if [[ "${PATRONI_NODES[$idx]}" == "${leader_ip}" ]]; then
    leader_slot=$((idx+1))
    break
  fi
done
if [[ "${leader_slot}" -eq 0 ]]; then
  fail "Patroni leader ${leader_ip} not found in node list"
fi

haproxy_status="$(ssh "${ssh_opts[@]}" -J "${jump_host}" "samakia@${HAPROXY_NODES[0]}" \
  "curl -s 'http://127.0.0.1:8404/;csv' | awk -F, '\$1==\"postgres_primary\" && \$2==\"pg_${leader_slot}\" {print \$18; exit}'")"
if [[ "${haproxy_status}" != "UP" ]]; then
  fail "haproxy reports pg_${leader_slot} as ${haproxy_status:-<empty>} (expected UP)"
fi
pass "HAProxy backend aligns with Patroni leader (pg_${leader_slot})"

# 6) DNS sanity (direct resolver)
dig +short "@${DNS_VIP}" "${DNS_PRIMARY}" A >/dev/null || fail "DNS A record missing for ${DNS_PRIMARY}"
dig +short "@${DNS_VIP}" "${DNS_ALIAS}" CNAME >/dev/null || fail "DNS CNAME missing for ${DNS_ALIAS}"
pass "DNS entries present for ${DNS_PRIMARY} and ${DNS_ALIAS}"

pass "Internal Postgres acceptance complete"
