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

PATRONI_NODES=("10.10.120.23" "10.10.120.24" "10.10.120.25")
PATRONI_PORT="8008"
POSTGRES_PORT="5432"

EDGE_JUMP=("192.168.11.106" "192.168.11.107")

CA_FILE_DEFAULT="${HOME}/.config/samakia-fabric/pki/postgres-internal-ca.crt"
CA_FILE="${POSTGRES_INTERNAL_CA_FILE:-${CA_FILE_DEFAULT}}"

usage() {
  cat >&2 <<'EOT'
Usage:
  postgres-internal-doctor.sh

Read-only health checks for internal Postgres (Patroni + HAProxy).
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
need python3

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

primary_ips="$(dig +short "@${DNS_VIP}" "${DNS_PRIMARY}" A | sort -u | tr '\n' ' ')"
if [[ -z "${primary_ips}" ]]; then
  fail "DNS did not resolve ${DNS_PRIMARY} via ${DNS_VIP}"
fi
pass "DNS resolves ${DNS_PRIMARY} via ${DNS_VIP}"

primary_ip="$(awk '{print $1}' <<< "${primary_ips}")"
if [[ -z "${primary_ip}" ]]; then
  fail "DNS did not return usable A records for ${DNS_PRIMARY} via ${DNS_VIP}"
fi

alias_target="$(dig +short "@${DNS_VIP}" "${DNS_ALIAS}" CNAME | tr -d '\r')"
if [[ "${alias_target}" != "${DNS_PRIMARY}." ]]; then
  fail "DNS alias mismatch for ${DNS_ALIAS}: expected ${DNS_PRIMARY}. got ${alias_target:-<empty>}"
fi
pass "DNS resolves ${DNS_ALIAS} -> ${DNS_PRIMARY}"

if [[ ! -f "${CA_FILE}" ]]; then
  fail "Postgres CA file missing: ${CA_FILE}"
fi

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

probe_host="${PATRONI_NODES[0]}"
remote_ca="/tmp/postgres-internal-ca.crt"

ssh "${ssh_opts[@]}" -J "${jump_host}" "samakia@${probe_host}" "cat > ${remote_ca}" < "${CA_FILE}"

ssh "${ssh_opts[@]}" -J "${jump_host}" "samakia@${probe_host}" \
  "python3 - '${primary_ip}' '${DNS_PRIMARY}' '${POSTGRES_PORT}' '${remote_ca}' '${PATRONI_PORT}' '${PATRONI_NODES[*]}'" <<'PY'
import json
import socket
import ssl
import sys
import urllib.request

ip = sys.argv[1]
host = sys.argv[2]
port = int(sys.argv[3])
ca_file = sys.argv[4]
rest_port = int(sys.argv[5])
patroni_nodes = sys.argv[6].split()

ctx = ssl.create_default_context(cafile=ca_file)
ctx.check_hostname = True
ctx.verify_mode = ssl.CERT_REQUIRED
sock = socket.create_connection((ip, port), timeout=5)
try:
    import struct
    sock.sendall(struct.pack("!ii", 8, 80877103))
    resp = sock.recv(1)
    if resp != b"S":
        raise RuntimeError(f"postgres SSL negotiation failed: {resp!r}")
    tls_sock = ctx.wrap_socket(sock, server_hostname=host)
    tls_sock.getpeercert()
    tls_sock.close()
except Exception as exc:
    raise SystemExit(f"FAIL: TLS handshake failed for {host}:{port}: {exc}")

roles = []
for ip in patroni_nodes:
    url = f"http://{ip}:{rest_port}/patroni"
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except Exception as exc:
        raise SystemExit(f"FAIL: Patroni API unreachable on {ip}:{rest_port}: {exc}")
    role = str(payload.get("role") or "")
    state = str(payload.get("state") or "")
    if state.lower() not in {"running", "streaming", "replicating"}:
        raise SystemExit(f"FAIL: Patroni state not healthy on {ip}: {state}")
    roles.append(role.lower())

leaders = [r for r in roles if r in {"leader", "master", "primary"}]
replicas = [r for r in roles if r in {"replica", "standby", "secondary"}]
if len(leaders) != 1:
    raise SystemExit(f"FAIL: expected 1 Patroni leader, got {len(leaders)}")
if len(replicas) < 2:
    raise SystemExit(f"FAIL: expected >=2 Patroni replicas, got {len(replicas)}")

print("PASS: TLS handshake + Patroni health")
PY

ssh "${ssh_opts[@]}" -J "${jump_host}" "samakia@${probe_host}" "rm -f ${remote_ca}" >/dev/null 2>&1 || true

pass "Patroni API reachable and TLS handshake verified"
