#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"

VAULT_VIP="192.168.11.121"
VAULT_PORT="8200"
VAULT_CA_DEFAULT="${HOME}/.config/samakia-fabric/pki/shared-bootstrap-ca.crt"
EDGE_LANS=("192.168.11.106" "192.168.11.107")

usage() {
  cat >&2 <<'EOF'
Usage:
  shared-vault-accept.sh

Read-only Vault acceptance tests for shared control plane.

Checks:
  - Vault VIP health endpoint reachable over strict TLS
  - Vault status reports initialized + unsealed
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
need python3

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

ca_path="${VAULT_CA_SRC:-${SHARED_EDGE_CA_SRC:-${VAULT_CA_DEFAULT}}}"
if [[ ! -f "${ca_path}" ]]; then
  echo "[FAIL] shared CA not found: ${ca_path} (run shared PKI setup first)" >&2
  exit 1
fi

ok() { echo "[OK] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }
check() { echo "[CHECK] $*"; }

check "Vault VIP health over TLS"
code="$(curl --cacert "${ca_path}" -sS -o /dev/null -w '%{http_code}' "https://${VAULT_VIP}:${VAULT_PORT}/v1/sys/health" || true)"
if [[ "${code}" != "200" && "${code}" != "429" && "${code}" != "472" ]]; then
  fail "vault health endpoint returned unexpected HTTP code: ${code}"
fi
ok "vault VIP health endpoint reachable (http_code=${code})"

# Use vault-1 via SSH to avoid DNS dependency
ssh_run() {
  local host="$1"
  shift
  local args=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
  if [[ -n "${SSH_JUMP:-}" ]]; then
    args+=(-o "ProxyJump=${SSH_JUMP}")
  fi
  # shellcheck disable=SC2029
  # Intentional remote execution via ssh wrapper.
  ssh "${args[@]}" "samakia@${host}" "$@"
}

SSH_JUMP=""
for edge in "${EDGE_LANS[@]}"; do
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "samakia@${edge}" true >/dev/null 2>&1; then
    SSH_JUMP="samakia@${edge}"
    break
  fi
done
if [[ -z "${SSH_JUMP}" ]]; then
  fail "no reachable shared edge for ProxyJump (${EDGE_LANS[*]}); cannot reach vault over VLAN"
fi

vault_status_json=""
if ! vault_status_json="$(ssh_run "10.10.120.21" "VAULT_ADDR=https://10.10.120.21:8200 VAULT_CACERT=/etc/vault/ssl/shared-bootstrap-ca.crt vault status -format=json" 2>/tmp/vault-status.err)"; then
  err_line="$(head -n 1 /tmp/vault-status.err 2>/dev/null || true)"
  fail "vault status command failed on vault-1 (ssh/vault CLI): ${err_line:-unknown error}"
fi
if [[ -z "${vault_status_json}" ]]; then
  err_line="$(head -n 1 /tmp/vault-status.err 2>/dev/null || true)"
  fail "vault status returned empty output on vault-1: ${err_line:-unknown error}"
fi

python3 - <<'PY' "${vault_status_json}"
import json
import sys

payload = json.loads(sys.argv[1])
if not payload.get("initialized"):
    raise SystemExit("[FAIL] vault is not initialized")
if payload.get("sealed"):
    raise SystemExit("[FAIL] vault is sealed")
print("[OK] vault initialized and unsealed")
PY

ok "Shared Vault acceptance completed"
