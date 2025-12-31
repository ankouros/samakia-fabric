#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

tmp_dir=""
cleanup() {
  if [[ -n "${tmp_dir}" ]]; then
    rm -rf "${tmp_dir}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

mode="${SSH_DRYRUN_MODE:-local}"

if [[ -z "${OPERATOR_KEYS_FILE:-}" || ! -f "${OPERATOR_KEYS_FILE}" ]]; then
  if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "ERROR: ssh-keygen not found (required to create sample keys for dry-run)" >&2
    exit 1
  fi
  tmp_dir="$(mktemp -d)"
  key_path="${tmp_dir}/sample_key"
  ssh-keygen -t ed25519 -f "${key_path}" -N "" >/dev/null
  sample_keys="${tmp_dir}/authorized_keys"
  cat "${key_path}.pub" > "${sample_keys}"
  export OPERATOR_KEYS_FILE="${sample_keys}"
  echo "INFO: OPERATOR_KEYS_FILE not found; using temporary sample key for dry-run" >&2
fi

if [[ "${mode}" == "remote" ]]; then
  exec bash "${FABRIC_REPO_ROOT}/ops/security/ssh/ssh-keys-rotate.sh" --dry-run
fi

if [[ "${mode}" != "local" ]]; then
  echo "ERROR: invalid SSH_DRYRUN_MODE=${mode} (expected local or remote)" >&2
  exit 1
fi

if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "ERROR: ssh-keygen not found (required for dry-run diff)" >&2
  exit 1
fi

current_keys="${AUTHORIZED_KEYS_FILE:-}"
if [[ -z "${current_keys}" || ! -f "${current_keys}" ]]; then
  if [[ -z "${tmp_dir}" ]]; then
    tmp_dir="$(mktemp -d)"
  fi
  current_keys="${tmp_dir}/authorized_keys.current"
  : > "${current_keys}"
  echo "INFO: AUTHORIZED_KEYS_FILE not set; using empty local authorized_keys for diff" >&2
fi

current_fps="$(ssh-keygen -lf "${current_keys}" 2>/dev/null | awk '{print $2}' | sort || true)"
new_fps="$(ssh-keygen -lf "${OPERATOR_KEYS_FILE}" 2>/dev/null | awk '{print $2}' | sort || true)"

added="$(comm -13 <(printf '%s\n' "${current_fps}") <(printf '%s\n' "${new_fps}") | sed '/^$/d' || true)"
removed="$(comm -23 <(printf '%s\n' "${current_fps}") <(printf '%s\n' "${new_fps}") | sed '/^$/d' || true)"

echo "SSH dry-run (local):"
echo "  current_fingerprints_count=$(printf '%s\n' "${current_fps}" | sed '/^$/d' | wc -l | awk '{print $1}')"
echo "  new_fingerprints_count=$(printf '%s\n' "${new_fps}" | sed '/^$/d' | wc -l | awk '{print $1}')"
echo "  added_fingerprints_count=$(printf '%s\n' "${added}" | sed '/^$/d' | wc -l | awk '{print $1}')"
echo "  removed_fingerprints_count=$(printf '%s\n' "${removed}" | sed '/^$/d' | wc -l | awk '{print $1}')"

echo "PASS: local ssh key diff computed (no changes applied)"
