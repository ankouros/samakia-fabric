#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"

MINIO_VIP="192.168.11.101"
MINIO_S3_PORT="9000"
MINIO_S3_HOSTNAME="minio.infra.samakia.net"

EDGE1_LAN="192.168.11.111"
EDGE2_LAN="192.168.11.112"

NODES_VLAN=("10.10.140.11" "10.10.140.12" "10.10.140.13")

usage() {
  cat >&2 <<'EOF'
Usage:
  minio-accept.sh

Non-interactive MinIO HA acceptance tests for Samakia Fabric (Terraform S3 backend).
Validates:
  - VIP HTTPS health endpoint (strict TLS)
  - keepalived + haproxy running on both edges
  - exactly one edge holds the VIP at a time
  - backend nodes respond (health)
  - mc can list the terraform bucket (via pre-configured alias on edge)
  - ansible idempotency (state-backend.yml changed=0)

EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "FAIL: missing required command: $1" >&2; exit 1; }
}

need curl
need ssh
need grep
need awk

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

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

bucket="${TF_BACKEND_S3_BUCKET:-}"
if [[ -z "${bucket}" ]]; then
  fail "TF_BACKEND_S3_BUCKET is missing in the runner environment"
fi

endpoint_host="${MINIO_VIP}"
if command -v getent >/dev/null 2>&1; then
  if getent ahostsv4 "${MINIO_S3_HOSTNAME}" >/dev/null 2>&1; then
    endpoint_host="${MINIO_S3_HOSTNAME}"
  fi
fi

###############################################################################
# 1) VIP reachable with strict TLS
###############################################################################

if ! curl -fsS "https://${endpoint_host}:${MINIO_S3_PORT}/minio/health/live" >/dev/null; then
  fail "MinIO VIP health endpoint failed (strict TLS): https://${endpoint_host}:${MINIO_S3_PORT}/minio/health/live"
fi
pass "MinIO VIP health endpoint OK (strict TLS, endpoint=${endpoint_host})"

###############################################################################
# 2) Edge services and VIP ownership
###############################################################################

for host in "${EDGE1_LAN}" "${EDGE2_LAN}"; do
  if ! ssh_run "${host}" systemctl is-active --quiet keepalived; then
    fail "keepalived not active on ${host}"
  fi
  if ! ssh_run "${host}" systemctl is-active --quiet haproxy; then
    fail "haproxy not active on ${host}"
  fi
done
pass "keepalived + haproxy active on both minio-edge nodes"

vip_holders=0
active_host=""
for host in "${EDGE1_LAN}" "${EDGE2_LAN}"; do
  if ssh_run "${host}" "ip -4 addr show | grep -q \"${MINIO_VIP}/\""; then
    vip_holders=$((vip_holders + 1))
    active_host="${host}"
  fi
done
if [[ "${vip_holders}" -ne 1 ]]; then
  fail "Expected exactly one VIP holder for ${MINIO_VIP}; got ${vip_holders}"
fi
pass "Exactly one minio-edge holds ${MINIO_VIP} (active=${active_host})"

###############################################################################
# 3) Backend nodes health (via active edge)
###############################################################################

for ip in "${NODES_VLAN[@]}"; do
  if ! ssh_run "${active_host}" "curl -fsS http://${ip}:${MINIO_S3_PORT}/minio/health/live >/dev/null"; then
    fail "MinIO node health failed (via edge): ${ip}"
  fi
done
pass "All MinIO backend nodes report healthy (via edge)"

###############################################################################
# 4) Bucket exists and terraform credentials work (via edge mc aliases)
###############################################################################

if ! ssh_run "${active_host}" "sudo /usr/local/bin/mc ls samakia-tf/${bucket} >/dev/null"; then
  fail "terraform user could not list bucket via mc alias (bucket=${bucket})"
fi
pass "terraform user can list bucket via mc alias (bucket=${bucket})"

if ! ssh_run "${active_host}" "sudo /usr/local/bin/mc admin info samakia-root >/dev/null"; then
  fail "minio admin info failed via mc (root alias)"
fi
pass "minio admin info OK via mc (root alias)"

###############################################################################
# 5) Idempotency
###############################################################################

if command -v ansible-playbook >/dev/null 2>&1; then
  out="$(ANSIBLE_CONFIG=fabric-core/ansible/ansible.cfg FABRIC_TERRAFORM_ENV=samakia-minio ansible-playbook -i fabric-core/ansible/inventory/terraform.py fabric-core/ansible/playbooks/state-backend.yml -u samakia 2>&1 || true)"
  if echo "${out}" | grep -Eq 'changed=[1-9]'; then
    echo "${out}" >&2
    fail "state-backend.yml is not idempotent (changed>0 on re-run)"
  fi
  if echo "${out}" | grep -Eq 'failed=[1-9]|unreachable=[1-9]'; then
    echo "${out}" >&2
    fail "state-backend.yml re-run had failures/unreachable"
  fi
  pass "state-backend.yml idempotency (changed=0)"
else
  echo "WARN: ansible-playbook not found; skipping idempotency check" >&2
fi

pass "MinIO acceptance suite complete"
