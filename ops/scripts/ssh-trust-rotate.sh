#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOF'
Usage:
  ssh-trust-rotate.sh --host <ip|hostname> [--port 22] [--enroll] [--expected-fingerprint <SHA256:...>]

Performs a strict known_hosts rotation workflow:
  1) Remove existing known_hosts entry: ssh-keygen -R
  2) Optional enrollment via ssh-keyscan (NOT a trust anchor by itself)
  3) Optional out-of-band fingerprint verification against an expected fingerprint

Hard rule:
  - Never disables StrictHostKeyChecking globally.
EOF
}

host=""
port="22"
enroll=0
expected=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      host="${2:-}"
      shift 2
      ;;
    --port)
      port="${2:-22}"
      shift 2
      ;;
    --enroll)
      enroll=1
      shift 1
      ;;
    --expected-fingerprint)
      expected="${2:-}"
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

if [[ -z "${host}" ]]; then
  usage
  exit 2
fi

command -v ssh-keygen >/dev/null 2>&1 || { echo "ERROR: ssh-keygen not found"; exit 1; }

echo "Removing known_hosts entries for ${host}..."
ssh-keygen -R "${host}" >/dev/null 2>&1 || true

if [[ "${enroll}" -eq 0 ]]; then
  echo "OK: rotation complete (enrollment skipped)."
  echo "Next (recommended): verify host key out-of-band, then enroll with:"
  echo "  ssh-trust-rotate.sh --host ${host} --port ${port} --enroll --expected-fingerprint <SHA256:...>"
  exit 0
fi

command -v ssh-keyscan >/dev/null 2>&1 || { echo "ERROR: ssh-keyscan not found"; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "${tmp}" 2>/dev/null || true' EXIT

ssh-keyscan -p "${port}" -T 5 "${host}" >"${tmp}" 2>/dev/null || true
if [[ ! -s "${tmp}" ]]; then
  echo "ERROR: ssh-keyscan returned no keys for ${host}:${port}" >&2
  exit 1
fi

if [[ -n "${expected}" ]]; then
  found=0
  while IFS= read -r line; do
    key="${line#* }"
    fp="$(printf '%s\n' "${key}" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')"
    if [[ "${fp}" == "${expected}" ]]; then
      found=1
      break
    fi
  done < <(grep -Ev '^\s*#|^\s*$' "${tmp}" || true)

  if [[ "${found}" -ne 1 ]]; then
    echo "ERROR: expected fingerprint not found in scanned keys (refusing enrollment)." >&2
    echo "Expected: ${expected}" >&2
    echo "Hint: verify the host key fingerprint out-of-band (Proxmox console / change record) and retry." >&2
    exit 1
  fi
fi

mkdir -p "${HOME}/.ssh"
touch "${HOME}/.ssh/known_hosts"
chmod 600 "${HOME}/.ssh/known_hosts" || true

cat "${tmp}" >>"${HOME}/.ssh/known_hosts"
echo "OK: enrolled host key(s) for ${host}:${port} into ~/.ssh/known_hosts"
