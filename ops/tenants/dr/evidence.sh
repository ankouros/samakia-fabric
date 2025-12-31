#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  evidence.sh --tenant <id> [--mode dry-run|execute]
EOT
}

tenant=""
mode="${DR_MODE:-dry-run}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)
      tenant="${2:-}"
      shift 2
      ;;
    --mode)
      mode="${2:-}"
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

if [[ -z "${tenant}" ]]; then
  echo "ERROR: --tenant is required" >&2
  usage
  exit 2
fi

bash "${FABRIC_REPO_ROOT}/ops/tenants/dr/run.sh" --tenant "${tenant}" --mode "${mode}"
