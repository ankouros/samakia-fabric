#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

SNAPSHOT_DIR="${1:-}"
if [[ -z "${SNAPSHOT_DIR}" ]]; then
  echo "Usage: $0 <snapshot-dir>" >&2
  echo "Example: $0 compliance/samakia-prod/snapshot-20250101T010203Z" >&2
  exit 2
fi

if [[ ! -d "${SNAPSHOT_DIR}" ]]; then
  echo "ERROR: snapshot directory not found: ${SNAPSHOT_DIR}" >&2
  exit 1
fi

require_cmd sha256sum
require_cmd gpg
require_cmd mktemp
require_cmd chmod
require_cmd python3

manifest="${SNAPSHOT_DIR}/manifest.sha256"
sig_single="${SNAPSHOT_DIR}/manifest.sha256.asc"
sig_a="${SNAPSHOT_DIR}/manifest.sha256.asc.a"
sig_b="${SNAPSHOT_DIR}/manifest.sha256.asc.b"
dual_required_marker="${SNAPSHOT_DIR}/DUAL_CONTROL_REQUIRED"
tsr="${SNAPSHOT_DIR}/manifest.sha256.tsr"

if [[ ! -f "${manifest}" ]]; then
  echo "ERROR: missing manifest: ${manifest}" >&2
  exit 1
fi

echo "Verifying manifest checksums..."
(
  cd "${SNAPSHOT_DIR}"
  sha256sum -c "manifest.sha256" >/dev/null
)

tmp_gnupg="$(mktemp -d)"
cleanup() { rm -rf "${tmp_gnupg}"; }
trap cleanup EXIT
chmod 700 "${tmp_gnupg}"

shopt -s nullglob
for pub in "${SNAPSHOT_DIR}"/signer-publickey*.asc; do
  gpg --homedir "${tmp_gnupg}" --batch --import "${pub}" >/dev/null 2>&1 || true
done
shopt -u nullglob

if [[ -f "${dual_required_marker}" ]]; then
  if [[ ! -s "${sig_a}" || ! -s "${sig_b}" ]]; then
    echo "ERROR: dual-control required but missing signature(s): ${sig_a} and/or ${sig_b}" >&2
    exit 1
  fi

  echo "Verifying dual-control signatures..."
  gpg --homedir "${tmp_gnupg}" --batch --verify "${sig_a}" "${manifest}" >/dev/null
  gpg --homedir "${tmp_gnupg}" --batch --verify "${sig_b}" "${manifest}" >/dev/null
else
  if [[ -s "${sig_single}" ]]; then
    echo "Verifying signature..."
    gpg --homedir "${tmp_gnupg}" --batch --verify "${sig_single}" "${manifest}" >/dev/null
  elif [[ -s "${sig_a}" && -s "${sig_b}" ]]; then
    echo "Verifying dual-control signatures..."
    gpg --homedir "${tmp_gnupg}" --batch --verify "${sig_a}" "${manifest}" >/dev/null
    gpg --homedir "${tmp_gnupg}" --batch --verify "${sig_b}" "${manifest}" >/dev/null
  else
    echo "ERROR: no signature found (expected ${sig_single} or ${sig_a}+${sig_b})." >&2
    exit 1
  fi
fi

if [[ -f "${tsr}" ]]; then
  require_cmd openssl

  tsa_ca="${SNAPSHOT_DIR}/tsa-ca.pem"
  if [[ ! -f "${tsa_ca}" ]]; then
    tsa_ca="${COMPLIANCE_TSA_CA:-}"
  fi

  if [[ -z "${tsa_ca}" || ! -f "${tsa_ca}" ]]; then
    echo "ERROR: TSA token present but no TSA CA bundle available (expected ${SNAPSHOT_DIR}/tsa-ca.pem or COMPLIANCE_TSA_CA)." >&2
    exit 1
  fi

  echo "Verifying TSA timestamp token..."
  openssl ts -verify -data "${manifest}" -in "${tsr}" -CAfile "${tsa_ca}" >/dev/null 2>&1

  ts_utc="$(
    openssl ts -reply -in "${tsr}" -text 2>/dev/null \
      | python3 -c 'import re,sys; text=sys.stdin.read(); m=re.search(r"(?m)^Time stamp:\\s*(.+?)\\s*$", text); print(m.group(1) if m else "unknown")'
  )"
  echo "OK: TSA timestamp: ${ts_utc}"
fi

echo "OK: snapshot verified: ${SNAPSHOT_DIR}"
