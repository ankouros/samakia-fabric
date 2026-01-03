#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


CA_DST="/usr/local/share/ca-certificates/samakia-fabric-s3-backend-ca.crt"

usage() {
  cat >&2 <<'EOF'
Usage:
  install-s3-backend-ca.sh [--src <ca.crt>]

Installs the MinIO/S3 backend CA into the host trust store (strict TLS).

Source selection:
  - If --src is not provided, uses TF_BACKEND_S3_CA_SRC from the environment.

Requires:
  - sudo privileges on the runner host
  - update-ca-certificates (Debian/Ubuntu)
EOF
}

src="${TF_BACKEND_S3_CA_SRC:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --src)
      src="${2:-}"
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

if [[ -z "${src}" ]]; then
  echo "ERROR: CA source not set. Provide --src or set TF_BACKEND_S3_CA_SRC." >&2
  exit 1
fi

if [[ ! -f "${src}" ]]; then
  echo "ERROR: CA source file not found: ${src}" >&2
  exit 1
fi

if ! command -v update-ca-certificates >/dev/null 2>&1; then
  echo "ERROR: update-ca-certificates not found (expected on Debian/Ubuntu hosts)" >&2
  exit 1
fi

echo "Installing S3 backend CA into host trust store..."
sudo install -m 0644 "${src}" "${CA_DST}"
sudo update-ca-certificates
echo "OK: installed ${CA_DST}"
