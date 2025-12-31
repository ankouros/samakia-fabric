#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  release-readiness-packet.sh <release-id> <env>

Wraps pre-release-readiness.sh and optionally signs the manifest.
EOT
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

release_id="${1:-}"
env_name="${2:-}"
if [[ -z "${release_id}" || -z "${env_name}" ]]; then
  usage
  exit 2
fi

require_cmd sha256sum

ALLOW_DIRTY_GIT="${ALLOW_DIRTY_GIT:-1}" \
  bash "${FABRIC_REPO_ROOT}/ops/scripts/pre-release-readiness.sh" "${release_id}" "${env_name}"

packet_dir="${FABRIC_REPO_ROOT}/release-readiness/${release_id}"
manifest="${packet_dir}/manifest.sha256"

if [[ ! -f "${manifest}" ]]; then
  echo "ERROR: manifest not found: ${manifest}" >&2
  exit 1
fi

if [[ "${EVIDENCE_SIGN:-0}" -eq 1 ]]; then
  if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg not found (required for EVIDENCE_SIGN=1)" >&2
    exit 1
  fi
  gpg_args=(--batch --yes --detach-sign)
  if [[ -n "${EVIDENCE_GPG_KEY:-}" ]]; then
    gpg_args+=(--local-user "${EVIDENCE_GPG_KEY}")
  fi
  gpg "${gpg_args[@]}" --output "${manifest}.asc" "${manifest}"
fi

echo "OK: wrote release readiness packet: ${packet_dir}"
