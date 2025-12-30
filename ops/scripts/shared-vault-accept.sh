#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"

VAULT_VIP="192.168.11.121"
VAULT_PORT="8200"
VAULT_CA_DEFAULT="${HOME}/.config/samakia-fabric/pki/shared-pki-ca.crt"

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

ca_path="${SHARED_EDGE_CA_SRC:-${VAULT_CA_DEFAULT}}"
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
  ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "samakia@${host}" "$@"
}

vault_status_json="$(ssh_run "10.10.120.21" "VAULT_ADDR=https://127.0.0.1:8200 VAULT_CACERT=/etc/vault/ssl/shared-bootstrap-ca.crt vault status -format=json" 2>/dev/null || true)"
if [[ -z "${vault_status_json}" ]]; then
  fail "vault status returned empty output on vault-1"
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
