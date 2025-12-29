#!/usr/bin/env bash
set -euo pipefail

DEFAULT_ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"
DEFAULT_CREDENTIALS_FILE="${HOME}/.config/samakia-fabric/credentials"
DEFAULT_PKI_DIR="${HOME}/.config/samakia-fabric/pki"

MINIO_S3_VIP_DEFAULT="192.168.11.101"
MINIO_S3_PORT_DEFAULT="9000"
MINIO_S3_HOSTNAME_DEFAULT="minio.infra.samakia.net"

usage() {
  cat >&2 <<'EOF'
Usage:
  backend-configure.sh [--file <env.sh>] [--credentials <path>] [--pki-dir <dir>]

Creates/updates runner-local configuration for the Terraform S3 backend (MinIO HA):
  - Generates local credentials file (chmod 600) if missing:
      MINIO_ROOT_USER / MINIO_ROOT_PASSWORD
      AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY   (terraform state user)
  - Generates local backend CA + HAProxy TLS pem if missing (under pki-dir)
  - Writes a managed block into env.sh (chmod 600) without printing secrets
  - Installs backend CA into host trust store (strict TLS) using sudo -n

Security:
  - Never prints secrets.
  - Never writes secrets into Git.
  - Requires non-interactive sudo for CA installation (or run as root).
EOF
}

env_file="${DEFAULT_ENV_FILE}"
credentials_file="${DEFAULT_CREDENTIALS_FILE}"
pki_dir="${DEFAULT_PKI_DIR}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      env_file="${2:-}"
      shift 2
      ;;
    --credentials)
      credentials_file="${2:-}"
      shift 2
      ;;
    --pki-dir)
      pki_dir="${2:-}"
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

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

require_cmd python3
require_cmd openssl
require_cmd install
require_cmd sudo

mkdir -p "$(dirname "${env_file}")" "$(dirname "${credentials_file}")" "${pki_dir}"
chmod 700 "$(dirname "${env_file}")" || true
chmod 700 "${pki_dir}" || true

if [[ ! -f "${credentials_file}" ]]; then
  echo "Creating credentials file (local-only; chmod 600): ${credentials_file}"
  python3 - <<'PY' "${credentials_file}"
import secrets
import string
import sys
from pathlib import Path

out = Path(sys.argv[1])
alphabet = string.ascii_letters + string.digits

def rand(n: int) -> str:
    return "".join(secrets.choice(alphabet) for _ in range(n))

content = "\n".join(
    [
        "# Samakia Fabric – local credentials (DO NOT COMMIT)",
        "export MINIO_ROOT_USER=" + repr(rand(20)),
        "export MINIO_ROOT_PASSWORD=" + repr(rand(40)),
        "export AWS_ACCESS_KEY_ID=" + repr(rand(20)),
        "export AWS_SECRET_ACCESS_KEY=" + repr(rand(40)),
        "",
    ]
)
tmp = out.with_suffix(".tmp")
tmp.write_text(content, encoding="utf-8")
tmp.chmod(0o600)
tmp.replace(out)
PY
else
  chmod 600 "${credentials_file}" || true
fi

ca_key="${pki_dir}/s3-backend-ca.key"
ca_crt="${pki_dir}/s3-backend-ca.crt"
server_key="${pki_dir}/minio-edge.key"
server_crt="${pki_dir}/minio-edge.crt"
server_pem="${pki_dir}/minio-edge.pem"

if [[ ! -f "${ca_key}" || ! -f "${ca_crt}" ]]; then
  echo "Generating backend CA (local-only): ${ca_crt}"
  openssl genrsa -out "${ca_key}" 4096 >/dev/null 2>&1
  chmod 600 "${ca_key}"
  openssl req -x509 -new -nodes \
    -key "${ca_key}" \
    -sha256 -days 3650 \
    -subj "/CN=Samakia Fabric S3 Backend CA" \
    -out "${ca_crt}" >/dev/null 2>&1
  chmod 644 "${ca_crt}"
fi

if [[ ! -f "${server_key}" || ! -f "${server_crt}" || ! -f "${server_pem}" ]]; then
  echo "Generating HAProxy TLS certificate (local-only): ${server_pem}"
  openssl genrsa -out "${server_key}" 2048 >/dev/null 2>&1
  chmod 600 "${server_key}"

  openssl req -new \
    -key "${server_key}" \
    -subj "/CN=minio.infra.samakia.net" \
    -out "${pki_dir}/minio-edge.csr" >/dev/null 2>&1

  cat >"${pki_dir}/minio-edge.ext" <<EOF
subjectAltName=DNS:minio.infra.samakia.net,DNS:minio-console.infra.samakia.net,IP:${MINIO_S3_VIP_DEFAULT}
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF

  openssl x509 -req \
    -in "${pki_dir}/minio-edge.csr" \
    -CA "${ca_crt}" \
    -CAkey "${ca_key}" \
    -CAcreateserial \
    -out "${server_crt}" \
    -days 825 \
    -sha256 \
    -extfile "${pki_dir}/minio-edge.ext" >/dev/null 2>&1
  chmod 644 "${server_crt}"

  cat "${server_key}" "${server_crt}" "${ca_crt}" >"${server_pem}"
  chmod 600 "${server_pem}"
fi

managed_begin="# >>> Samakia Fabric backend (managed)"
managed_end="# <<< Samakia Fabric backend (managed)"

endpoint="https://${MINIO_S3_VIP_DEFAULT}:${MINIO_S3_PORT_DEFAULT}"
if command -v getent >/dev/null 2>&1; then
  if getent ahostsv4 "${MINIO_S3_HOSTNAME_DEFAULT}" >/dev/null 2>&1; then
    endpoint="https://${MINIO_S3_HOSTNAME_DEFAULT}:${MINIO_S3_PORT_DEFAULT}"
  fi
fi

managed_block="$(
  cat <<EOF
${managed_begin}
# Terraform S3 backend (MinIO-compatible, strict TLS via host trust store)
export TF_BACKEND_S3_ENDPOINT='${endpoint}'
export TF_BACKEND_S3_BUCKET='samakia-terraform'
export TF_BACKEND_S3_REGION='us-east-1'
export TF_BACKEND_S3_KEY_PREFIX='samakia-fabric'
export TF_BACKEND_S3_CA_REQUIRED='1'
export TF_BACKEND_S3_CA_SRC='${ca_crt}'

# HAProxy TLS bundle for minio-edge (private key local-only)
export MINIO_EDGE_LB_TLS_PEM_SRC='${server_pem}'

# Local credentials (never commit)
source '${credentials_file}'
${managed_end}
EOF
)"

python3 - <<'PY' "${env_file}" "${managed_begin}" "${managed_end}" "${managed_block}"
import sys
from pathlib import Path

env_file = Path(sys.argv[1])
begin = sys.argv[2]
end = sys.argv[3]
block = sys.argv[4]

env_file.parent.mkdir(parents=True, exist_ok=True)

text = env_file.read_text(encoding="utf-8") if env_file.exists() else ""
lines = text.splitlines()

out: list[str] = []
inside = False
found = False
for line in lines:
    if line.strip() == begin:
        inside = True
        found = True
        continue
    if inside and line.strip() == end:
        inside = False
        continue
    if not inside:
        out.append(line)

if out and out[-1].strip() != "":
    out.append("")

out.append(block)
out.append("")

tmp = env_file.with_suffix(".tmp")
tmp.write_text("\n".join(out) + "\n", encoding="utf-8")
tmp.chmod(0o600)
tmp.replace(env_file)
PY

chmod 600 "${env_file}" || true

echo "Installing backend CA into host trust store (strict TLS)..."
if command -v sudo >/dev/null 2>&1; then
  if sudo -n true 2>/dev/null; then
    TF_BACKEND_S3_CA_SRC="${ca_crt}" bash ops/scripts/install-s3-backend-ca.sh >/dev/null
  else
    echo "ERROR: sudo non-interactive check failed; CA install requires NOPASSWD or root." >&2
    echo "Run: sudo bash ops/scripts/install-s3-backend-ca.sh --src ${ca_crt}" >&2
    exit 1
  fi
else
  echo "ERROR: sudo not found; cannot install CA into trust store." >&2
  exit 1
fi

echo "OK: backend configured (env file + credentials + CA + TLS bundle)."
echo "Next:"
echo "  source ${env_file}"
echo "  bash ops/scripts/runner-env-check.sh --file ${env_file}"
