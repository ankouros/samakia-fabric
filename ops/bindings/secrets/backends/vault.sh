#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  vault.sh <command> [args]

Commands:
  get <key> [field]   Fetch a secret value (stdout)
  list [path]         List available keys (no values)
  doctor              Show backend configuration (no secrets)

Notes:
  - Vault backend is read-only for bindings.
EOT
}

cmd="${1:-}"
shift $(( $# >= 1 ? 1 : $# ))

if [[ -z "${cmd}" || "${cmd}" == "-h" || "${cmd}" == "--help" ]]; then
  usage
  exit 0
fi

case "${cmd}" in
  get|list|doctor)
    exec bash "${FABRIC_REPO_ROOT}/ops/secrets/secrets-vault.sh" "${cmd}" "$@"
    ;;
  put|write|set)
    echo "ERROR: vault backend is read-only for bindings" >&2
    exit 2
    ;;
  *)
    echo "ERROR: unsupported command: ${cmd}" >&2
    usage
    exit 2
    ;;
esac
