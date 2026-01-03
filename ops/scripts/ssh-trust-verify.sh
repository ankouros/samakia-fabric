#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOF'
Usage:
  ssh-trust-verify.sh --host <ip|hostname>

Prints the currently known host key fingerprints for a host from ~/.ssh/known_hosts.

This is for out-of-band verification workflows (no SSH connection required).
EOF
}

host=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      host="${2:-}"
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

kh="${HOME}/.ssh/known_hosts"
if [[ ! -f "${kh}" ]]; then
  echo "ERROR: ~/.ssh/known_hosts not found" >&2
  exit 1
fi

echo "Known host keys for ${host}:"
ssh-keygen -F "${host}" -f "${kh}" | grep -v '^#' || true

echo
echo "Fingerprints:"
ssh-keygen -F "${host}" -f "${kh}" | grep -v '^#' | while IFS= read -r line; do
  key="${line#* }"
  ssh-keygen -lf - <<<"${key}" 2>/dev/null || true
done
