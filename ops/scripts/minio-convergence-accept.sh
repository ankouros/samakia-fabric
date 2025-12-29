#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"

# Canonical VIP (LAN front door)
MINIO_VIP="192.168.11.101"
S3_PORT="9000"
CONSOLE_PORT="9001"

# Canonical VLAN-only MinIO nodes
MINIO_NODES=("10.10.140.11" "10.10.140.12" "10.10.140.13")

usage() {
  cat >&2 <<'EOF'
Usage:
  minio-convergence-accept.sh

Read-only MinIO cluster convergence acceptance checks.

Validates (non-destructive):
  A) VIP endpoint health over strict TLS (S3 + console)
  B) Cluster membership (N=3) and node/drives online via mc admin info (via edge)
  C) Distributed/erasure mode signals (best-effort via mc admin info output)
  D) Clock skew across nodes (<1s) (best-effort via SSH ProxyJump through edges)
  E) HA signals: keepalived/haproxy on both edges; VIP reachable from both edges; all backends healthy (via edge)
  F) Control-plane invariants: bucket exists; samakia-minio tfstate object exists; terraform user is not admin; anonymous access disabled

Notes:
  - Requires runner-local env (~/.config/samakia-fabric/env.sh) and backend CA installed (strict TLS).
  - Requires SSH to minio-edge mgmt IPs (allowlisted).
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
need ssh
need awk
need grep
need python3

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

check() { echo "[CHECK] $*"; }
ok() { echo "[OK] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

bucket="${TF_BACKEND_S3_BUCKET:-}"
key_prefix="${TF_BACKEND_S3_KEY_PREFIX:-samakia-fabric}"

if [[ -z "${bucket}" ]]; then
  fail "TF_BACKEND_S3_BUCKET is missing in runner env"
fi

edge1_lan="$(awk -F': ' '$1=="ansible_host"{print $2; exit}' "${FABRIC_REPO_ROOT}/fabric-core/ansible/host_vars/minio-edge-1.yml" 2>/dev/null || true)"
edge2_lan="$(awk -F': ' '$1=="ansible_host"{print $2; exit}' "${FABRIC_REPO_ROOT}/fabric-core/ansible/host_vars/minio-edge-2.yml" 2>/dev/null || true)"
if [[ -z "${edge1_lan}" || -z "${edge2_lan}" ]]; then
  fail "could not resolve minio-edge ansible_host from host_vars"
fi

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
# A) Endpoint health (strict TLS) + no plaintext exposure
###############################################################################

check "VIP S3 health over TLS"
curl -fsS "https://${MINIO_VIP}:${S3_PORT}/minio/health/live" >/dev/null
ok "VIP S3 health OK (TLS): https://${MINIO_VIP}:${S3_PORT}/minio/health/live"

check "VIP console reachable over TLS"
code="$(curl -sS -o /dev/null -w '%{http_code}' "https://${MINIO_VIP}:${CONSOLE_PORT}/" || true)"
if [[ "${code}" != "200" && "${code}" != "302" && "${code}" != "303" && "${code}" != "307" && "${code}" != "308" ]]; then
  fail "VIP console unexpected status over TLS: https://${MINIO_VIP}:${CONSOLE_PORT}/ (http_code=${code:-<empty>})"
fi
ok "VIP console reachable over TLS (http_code=${code})"

check "No plaintext HTTP exposed on VIP ports"
http_code="$(curl -sS -o /dev/null -w '%{http_code}' "http://${MINIO_VIP}:${S3_PORT}/minio/health/live" || true)"
if [[ "${http_code}" != "000" ]]; then
  fail "plaintext HTTP responded on VIP S3 port (expected no HTTP): http://${MINIO_VIP}:${S3_PORT}/... (http_code=${http_code})"
fi
http_code="$(curl -sS -o /dev/null -w '%{http_code}' "http://${MINIO_VIP}:${CONSOLE_PORT}/" || true)"
if [[ "${http_code}" != "000" ]]; then
  fail "plaintext HTTP responded on VIP console port (expected no HTTP): http://${MINIO_VIP}:${CONSOLE_PORT}/ (http_code=${http_code})"
fi
ok "No plaintext HTTP responses observed on VIP ports (best-effort)"

###############################################################################
# E) HA / VIP safety signals (edges)
###############################################################################

check "Edges services (keepalived + haproxy) active"
for host in "${edge1_lan}" "${edge2_lan}"; do
  ssh_run "${host}" systemctl is-active --quiet keepalived || fail "keepalived not active on ${host}"
  ssh_run "${host}" systemctl is-active --quiet haproxy || fail "haproxy not active on ${host}"
done
ok "keepalived + haproxy active on both edges"

check "Exactly one VIP holder"
vip_holders=0
active_edge=""
for host in "${edge1_lan}" "${edge2_lan}"; do
  if ssh_run "${host}" "ip -4 addr show | grep -q \"${MINIO_VIP}/\""; then
    vip_holders=$((vip_holders + 1))
    active_edge="${host}"
  fi
done
if [[ "${vip_holders}" -ne 1 ]]; then
  fail "expected exactly one VIP holder for ${MINIO_VIP}; got ${vip_holders}"
fi
ok "exactly one edge holds ${MINIO_VIP} (active=${active_edge})"

check "VIP reachable from both edges"
for host in "${edge1_lan}" "${edge2_lan}"; do
  ssh_run "${host}" "curl -fsS \"https://${MINIO_VIP}:${S3_PORT}/minio/health/live\" >/dev/null" \
    || fail "VIP not reachable from edge ${host}"
done
ok "VIP reachable from both edges (best-effort)"

check "All MinIO node health endpoints reachable via active edge"
for ip in "${MINIO_NODES[@]}"; do
  ssh_run "${active_edge}" "curl -fsS \"http://${ip}:${S3_PORT}/minio/health/live\" >/dev/null" \
    || fail "minio node health failed via active edge: ${ip}"
done
ok "all MinIO nodes report healthy via active edge"

###############################################################################
# B/C) Cluster membership & mode signals (mc admin info)
###############################################################################

check "mc admin info reports 3 online nodes (via active edge)"
admin_json="$(ssh_run "${active_edge}" "sudo /usr/local/bin/mc admin info samakia-root --json" 2>/dev/null || true)"
if [[ -z "${admin_json}" ]]; then
  fail "mc admin info returned empty output (active_edge=${active_edge})"
fi

python3 - <<'PY' "${admin_json}"
import json
import re
import sys

raw = sys.argv[1]

objs = []
for line in raw.splitlines():
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        objs.append(json.loads(line))
    except Exception:
        pass

if not objs:
    try:
        objs = [json.loads(raw)]
    except Exception as e:
        print(f"[FAIL] could not parse mc admin info JSON: {e}", file=sys.stderr)
        sys.exit(1)

text = json.dumps(objs)
for bad in ("offline", "healing", "rebalancing"):
    if re.search(rf"\\b{bad}\\b", text, flags=re.IGNORECASE):
        print(f"[FAIL] cluster state contains forbidden signal: {bad}", file=sys.stderr)
        sys.exit(1)

endpoints = set()
for obj in objs:
    # tolerate different mc output shapes
    for k in ("endpoint", "addr", "address", "host", "node"):
        v = obj.get(k)
        if isinstance(v, str) and v:
            endpoints.add(v)
    # some outputs include 'info' dict with 'addr'
    info = obj.get("info")
    if isinstance(info, dict):
        v = info.get("addr") or info.get("endpoint") or info.get("host")
        if isinstance(v, str) and v:
            endpoints.add(v)

ip_re = re.compile(r"(10\\.10\\.140\\.(11|12|13))")
ips = set(m.group(1) for m in ip_re.finditer(text))
if len(ips) != 3:
    print(f"[FAIL] expected exactly 3 minio node IPs in admin info; got {sorted(ips)}", file=sys.stderr)
    sys.exit(1)

print("[OK] mc admin info includes 3 minio node IPs and no offline/healing/rebalancing signals")
PY

ok "cluster membership & state signals OK (best-effort)"

###############################################################################
# D) Clock skew (best-effort, via SSH ProxyJump through edges)
###############################################################################

check "Clock skew across MinIO nodes < 1s (best-effort)"
ts1="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -J "samakia@${edge1_lan},samakia@${edge2_lan}" "samakia@10.10.140.11" 'date +%s%N' 2>/dev/null || true)"
ts2="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -J "samakia@${edge1_lan},samakia@${edge2_lan}" "samakia@10.10.140.12" 'date +%s%N' 2>/dev/null || true)"
ts3="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -J "samakia@${edge1_lan},samakia@${edge2_lan}" "samakia@10.10.140.13" 'date +%s%N' 2>/dev/null || true)"

if [[ -z "${ts1}" || -z "${ts2}" || -z "${ts3}" ]]; then
  fail "could not read time from one or more minio nodes via ProxyJump (ensure nodes are reachable and samakia SSH works)"
fi

python3 - <<'PY' "${ts1}" "${ts2}" "${ts3}"
import sys

vals = [int(x) for x in sys.argv[1:]]
skew_ns = max(vals) - min(vals)
if skew_ns > 1_000_000_000:
    print(f"[FAIL] time skew exceeds 1s (skew_ns={skew_ns})", file=sys.stderr)
    sys.exit(1)
print(f"[OK] time skew within 1s (skew_ns={skew_ns})")
PY

###############################################################################
# F) Control-plane invariants (bucket/prefix/state object, auth posture)
###############################################################################

check "Terraform backend bucket exists (terraform user alias)"
ssh_run "${active_edge}" "sudo /usr/local/bin/mc ls samakia-tf/${bucket} >/dev/null" \
  || fail "terraform user could not list bucket via mc alias (bucket=${bucket})"
ok "bucket exists and terraform user can list (read access)"

check "samkia-minio tfstate object exists (post-migrate invariant)"
state_key="${key_prefix}/samakia-minio/terraform.tfstate"
ssh_run "${active_edge}" "sudo /usr/local/bin/mc stat samakia-tf/${bucket}/${state_key} >/dev/null" \
  || fail "expected tfstate object missing: s3://${bucket}/${state_key} (run minio.state.migrate after minio.up)"
ok "tfstate object exists: ${state_key}"

check "Terraform backend uses lockfiles (code invariant)"
grep -q "use_lockfile = true" "${FABRIC_REPO_ROOT}/ops/scripts/tf-backend-init.sh" \
  || fail "ops/scripts/tf-backend-init.sh missing use_lockfile = true (required lockfile contract)"
ok "use_lockfile=true present in backend init config"

check "Terraform user is not admin (best-effort)"
if ssh_run "${active_edge}" "sudo /usr/local/bin/mc admin info samakia-tf >/dev/null" 2>/dev/null; then
  fail "terraform user appears to have admin privileges (mc admin info succeeded for samakia-tf alias)"
fi
ok "terraform user is not admin (mc admin info fails as expected)"

check "Anonymous access disabled (best-effort)"
anon_out="$(ssh_run "${active_edge}" "sudo /usr/local/bin/mc anonymous get samakia-tf/${bucket} 2>/dev/null" || true)"
if ! echo "${anon_out}" | grep -qi "private"; then
  fail "anonymous access not confirmed private (output redacted); expected 'private'"
fi
ok "anonymous access appears disabled (bucket is private)"

ok "MinIO convergence acceptance completed"
