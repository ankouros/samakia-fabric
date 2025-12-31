#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  issue.sh --tenant <id> --consumer <consumer> [--endpoint <endpoint_ref>]

Guards:
  TENANT_CREDS_ISSUE=1

Optional:
  TENANT_CREDS_FILE            Override encrypted file path
  TENANT_CREDS_PASSPHRASE      Passphrase (env)
  TENANT_CREDS_PASSPHRASE_FILE Passphrase file
  SECRETS_BACKEND=vault        Optional Vault write mode (requires VAULT_WRITE=1)
EOT
}

tenant=""
consumer=""
endpoint_ref=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)
      tenant="${2:-}"
      shift 2
      ;;
    --consumer)
      consumer="${2:-}"
      shift 2
      ;;
    --endpoint)
      endpoint_ref="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${tenant}" || -z "${consumer}" ]]; then
  echo "ERROR: --tenant and --consumer are required" >&2
  usage
  exit 2
fi

if [[ "${TENANT_CREDS_ISSUE:-0}" != "1" ]]; then
  echo "ERROR: TENANT_CREDS_ISSUE=1 is required to issue credentials" >&2
  exit 2
fi

secrets_file_default="${HOME}/.config/samakia-fabric/tenants/${tenant}/creds.enc"
secrets_file="${TENANT_CREDS_FILE:-${secrets_file_default}}"
secrets_dir="$(dirname "${secrets_file}")"

pass_arg=()
if [[ -n "${TENANT_CREDS_PASSPHRASE_FILE:-}" ]]; then
  if [[ ! -f "${TENANT_CREDS_PASSPHRASE_FILE}" ]]; then
    echo "ERROR: TENANT_CREDS_PASSPHRASE_FILE not found: ${TENANT_CREDS_PASSPHRASE_FILE}" >&2
    exit 2
  fi
  pass_arg=( -pass "file:${TENANT_CREDS_PASSPHRASE_FILE}" )
elif [[ -n "${TENANT_CREDS_PASSPHRASE:-}" ]]; then
  pass_arg=( -pass env:TENANT_CREDS_PASSPHRASE )
fi

if [[ ${#pass_arg[@]} -eq 0 ]]; then
  echo "ERROR: passphrase not set (TENANT_CREDS_PASSPHRASE or TENANT_CREDS_PASSPHRASE_FILE)" >&2
  exit 2
fi

endpoints_path="${FABRIC_REPO_ROOT}/contracts/tenants/examples/${tenant}/endpoints.yml"
if [[ ! -f "${endpoints_path}" ]]; then
  echo "ERROR: endpoints file not found: ${endpoints_path}" >&2
  exit 1
fi

endpoint_ref="${endpoint_ref:-${consumer}-primary}"

endpoint_json=$(python3 - <<PY
import json
import sys
from pathlib import Path

path = Path("${endpoints_path}")
endpoint_ref = "${endpoint_ref}"

try:
    data = json.loads(path.read_text())
except json.JSONDecodeError as exc:
    print(f"ERROR: invalid JSON in {path}: {exc}", file=sys.stderr)
    sys.exit(2)

for ep in data.get("spec", {}).get("endpoints", []):
    if ep.get("name") == endpoint_ref:
        print(json.dumps(ep))
        sys.exit(0)

print(f"ERROR: endpoint_ref '{endpoint_ref}' not found in {path}", file=sys.stderr)
sys.exit(2)
PY
)

username=$(python3 - <<PY
import re
name = f"${tenant}_${consumer}"
name = re.sub(r"[^a-zA-Z0-9_-]", "_", name)
print(name)
PY
)

password=$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(24))
PY
)

issued_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "${secrets_dir}"

plaintext_tmp="$(mktemp)"
trap 'rm -f "${plaintext_tmp}"' EXIT

if [[ -f "${secrets_file}" ]]; then
  if ! openssl enc -d -aes-256-cbc -pbkdf2 -in "${secrets_file}" "${pass_arg[@]}" >"${plaintext_tmp}"; then
    echo "ERROR: failed to decrypt existing credentials file" >&2
    exit 2
  fi
else
  echo "{}" >"${plaintext_tmp}"
fi

python3 - <<PY
import json
from pathlib import Path

path = Path("${plaintext_tmp}")
raw = path.read_text()
try:
    data = json.loads(raw) if raw.strip() else {}
except json.JSONDecodeError:
    data = {}

entry = {
    "username": "${username}",
    "password": "${password}",
    "endpoint_ref": "${endpoint_ref}",
    "issued_at": "${issued_at}",
    "connection": json.loads('''${endpoint_json}''')
}

data["${consumer}"] = entry
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

openssl enc -aes-256-cbc -pbkdf2 -in "${plaintext_tmp}" -out "${secrets_file}" "${pass_arg[@]}"
chmod 600 "${secrets_file}"

if [[ "${SECRETS_BACKEND:-file}" == "vault" && "${VAULT_WRITE:-0}" == "1" ]]; then
  if ! command -v vault >/dev/null 2>&1; then
    echo "ERROR: vault CLI not found (required for VAULT_WRITE=1)" >&2
    exit 2
  fi
  vault_path="tenants/${tenant}/${consumer}"
  vault kv put "${vault_path}" username="${username}" password="${password}" >/dev/null
  echo "PASS: wrote credentials to vault://${vault_path}"
fi

evidence_root="${FABRIC_REPO_ROOT}/evidence/tenants/${tenant}/${issued_at}/creds"
mkdir -p "${evidence_root}"

cat >"${evidence_root}/report.md" <<EOF_REPORT
# Tenant Credential Issue

Tenant: ${tenant}
Consumer: ${consumer}
Endpoint ref: ${endpoint_ref}
Issued at (UTC): ${issued_at}

Secret storage: ${secrets_file}

Notes:
- Password stored in encrypted file and not printed.
EOF_REPORT

python3 - <<PY
import json
from pathlib import Path

data = {
    "tenant": "${tenant}",
    "consumer": "${consumer}",
    "endpoint_ref": "${endpoint_ref}",
    "issued_at": "${issued_at}",
    "secrets_file": "${secrets_file}",
    "username": "${username}",
    "connection": json.loads('''${endpoint_json}''')
}
Path("${evidence_root}/metadata.json").write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

( cd "${evidence_root}" && find . -type f ! -name "manifest.sha256" -print0 | sort -z | xargs -0 sha256sum > manifest.sha256 )

echo "PASS creds issue: ${tenant}/${consumer} (stored ${secrets_file})"
