#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"
VAULT_LOCAL_ADDR="https://10.10.120.21:8200"
ROOT_TOKEN_FILE="${HOME}/.config/samakia-fabric/vault/root-token"
EDGE_LANS=("192.168.11.106" "192.168.11.107")

usage() {
  cat >&2 <<'EOF'
Usage:
  shared-pki-accept.sh

Read-only PKI acceptance tests for shared control plane (Vault PKI).

Checks:
  - PKI engine enabled
  - CA certificate readable
  - Role for shared-services exists
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "[FAIL] missing required command: $1" >&2; exit 1; }
}

need ssh
need python3

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

if [[ ! -f "${ROOT_TOKEN_FILE}" ]]; then
  echo "[FAIL] Vault root token missing: ${ROOT_TOKEN_FILE} (run shared.secrets to initialize Vault)" >&2
  exit 1
fi

ok() { echo "[OK] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

root_token="$(cat "${ROOT_TOKEN_FILE}")"

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

secrets_json="$(ssh_run "10.10.120.21" "VAULT_ADDR=${VAULT_LOCAL_ADDR} VAULT_CACERT=/etc/vault/ssl/shared-bootstrap-ca.crt VAULT_TOKEN='${root_token}' vault secrets list -format=json" 2>/tmp/vault-pki.err || true)"
if [[ -z "${secrets_json}" ]]; then
  err_line="$(head -n 1 /tmp/vault-pki.err 2>/dev/null || true)"
  fail "vault secrets list returned empty output: ${err_line:-unknown error}"
fi

python3 - <<'PY' "${secrets_json}"
import json
import sys

payload = json.loads(sys.argv[1])
if "pki/" not in payload:
    raise SystemExit("[FAIL] vault PKI engine not enabled at pki/")
print("[OK] vault PKI engine enabled")
PY

ca_out="$(ssh_run "10.10.120.21" "VAULT_ADDR=${VAULT_LOCAL_ADDR} VAULT_CACERT=/etc/vault/ssl/shared-bootstrap-ca.crt VAULT_TOKEN='${root_token}' vault read -format=json pki/cert/ca" 2>/tmp/vault-pki.err || true)"
if [[ -z "${ca_out}" ]]; then
  err_line="$(head -n 1 /tmp/vault-pki.err 2>/dev/null || true)"
  fail "vault PKI CA certificate is empty: ${err_line:-unknown error}"
fi
python3 - <<'PY' "${ca_out}"
import json
import sys

payload = json.loads(sys.argv[1])
cert = (payload.get("data") or {}).get("certificate", "")
if not cert:
    raise SystemExit("[FAIL] vault PKI CA certificate missing in pki/cert/ca")
print("[OK] vault PKI CA certificate readable")
PY

role_out="$(ssh_run "10.10.120.21" "VAULT_ADDR=${VAULT_LOCAL_ADDR} VAULT_CACERT=/etc/vault/ssl/shared-bootstrap-ca.crt VAULT_TOKEN='${root_token}' vault read -format=json pki/roles/shared-services" 2>/tmp/vault-pki.err || true)"
if [[ -z "${role_out}" ]]; then
  err_line="$(head -n 1 /tmp/vault-pki.err 2>/dev/null || true)"
  fail "vault PKI role shared-services missing: ${err_line:-unknown error}"
fi
ok "vault PKI role shared-services present"

ok "Shared PKI acceptance completed"
