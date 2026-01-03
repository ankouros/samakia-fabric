#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  secrets.sh <command> [args]

Commands:
  get <key> [field]   Fetch a secret value (stdout)
  list [path]         List available keys (no values)
  doctor              Show backend configuration (no secrets)

Backend selection:
  SECRETS_BACKEND=vault  Vault backend (default by policy; set explicitly)
  SECRETS_BACKEND=file   Offline encrypted file (explicit exception)
EOT
}

cmd="${1:-}"
shift $(( $# >= 1 ? 1 : $# ))

if [[ -z "${cmd}" || "${cmd}" == "-h" || "${cmd}" == "--help" ]]; then
  usage
  exit 0
fi

backend="${SECRETS_BACKEND:-file}"

case "${backend}" in
  file)
    exec bash "${FABRIC_REPO_ROOT}/ops/secrets/secrets-file.sh" "${cmd}" "$@"
    ;;
  vault)
    exec bash "${FABRIC_REPO_ROOT}/ops/secrets/secrets-vault.sh" "${cmd}" "$@"
    ;;
  *)
    echo "ERROR: unsupported SECRETS_BACKEND=${backend} (expected file or vault)" >&2
    exit 2
    ;;
esac
