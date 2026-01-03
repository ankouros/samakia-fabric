#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  app-compliance-packet.sh <env> <service_name> <service_root_dir> [--config <paths.txt>] [--profile <path>] [--version <string>]

Wraps app-compliance-evidence.sh and optionally signs the manifest.

Options:
  --config <paths.txt>   Newline-separated relative paths from service_root_dir
  --profile <path>       Service compliance profile (docs-only)
  --version <string>     Service version/build identifier
EOT
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

ENV_NAME="${1:-}"
SERVICE_NAME="${2:-}"
SERVICE_ROOT="${3:-}"
shift $(( $# >= 3 ? 3 : $# ))

if [[ -z "${ENV_NAME}" || -z "${SERVICE_NAME}" || -z "${SERVICE_ROOT}" ]]; then
  usage
  exit 2
fi

require_cmd awk

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config|--profile|--version)
      args+=("$1" "${2:-}")
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

output="$(bash "${FABRIC_REPO_ROOT}/ops/scripts/app-compliance-evidence.sh" "${ENV_NAME}" "${SERVICE_NAME}" "${SERVICE_ROOT}" "${args[@]}" 2>&1)"
packet_dir="$(printf '%s\n' "${output}" | awk -F': ' '/^OK: wrote application evidence bundle:/{print $3; exit}')"

if [[ -z "${packet_dir}" ]]; then
  echo "ERROR: app compliance evidence generation failed" >&2
  printf '%s\n' "${output}" >&2
  exit 1
fi

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

printf '%s\n' "${output}"
