#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

file="${1:-}"
if [[ -z "${file}" ]]; then
  echo "usage: signer.sh <file>" >&2
  exit 1
fi

if [[ ! -f "${file}" ]]; then
  echo "ERROR: file not found: ${file}" >&2
  exit 1
fi

if [[ "${EVIDENCE_SIGN:-0}" != "1" ]]; then
  echo "SKIP: signing disabled"
  exit 0
fi

if [[ -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
  echo "ERROR: EVIDENCE_SIGN_KEY required when EVIDENCE_SIGN=1" >&2
  exit 2
fi

if ! command -v gpg >/dev/null 2>&1; then
  echo "ERROR: gpg not found (required for signing)" >&2
  exit 2
fi

gpg --batch --yes --armor --detach-sign -u "${EVIDENCE_SIGN_KEY}" "${file}"
