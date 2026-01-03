#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  gameday-service-restart.sh --service <name> --target <ip> [--dry-run|--execute] [--check-url <url>]

Safe service restart simulation. Default is --dry-run.
Execution requires GAMEDAY_EXECUTE=1.
EOT
}

SERVICE=""
TARGET=""
CHECK_URL=""
MODE="dry-run"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)
      SERVICE="${2:-}"
      shift 2
      ;;
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --check-url)
      CHECK_URL="${2:-}"
      shift 2
      ;;
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --execute)
      MODE="execute"
      shift
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

if [[ -z "${SERVICE}" || -z "${TARGET}" ]]; then
  echo "ERROR: --service and --target are required" >&2
  exit 2
fi

ssh_user="${GAMEDAY_SSH_USER:-samakia}"
ca_path="${OBS_CA_SRC:-${SHARED_EDGE_CA_SRC:-${HOME}/.config/samakia-fabric/pki/shared-bootstrap-ca.crt}}"

if [[ "${MODE}" == "dry-run" ]]; then
  echo "DRY-RUN: would restart ${SERVICE} on ${TARGET} via sudo systemctl"
  if [[ -n "${CHECK_URL}" ]]; then
    echo "DRY-RUN: would check readiness at ${CHECK_URL}"
  fi
  exit 0
fi

if [[ "${GAMEDAY_EXECUTE:-}" != "1" ]]; then
  echo "ERROR: execution requires GAMEDAY_EXECUTE=1" >&2
  exit 1
fi

ssh -o BatchMode=yes -o ConnectTimeout=5 "${ssh_user}@${TARGET}" "sudo -n systemctl restart ${SERVICE}"

if [[ -n "${CHECK_URL}" ]]; then
  if [[ ! -f "${ca_path}" ]]; then
    echo "ERROR: CA not found for readiness check: ${ca_path}" >&2
    exit 1
  fi
  code=$(curl --cacert "${ca_path}" -sS -o /dev/null -w "%{http_code}" "${CHECK_URL}" || true)
  if [[ "${code}" != "200" && "${code}" != "302" && "${code}" != "429" && "${code}" != "472" && "${code}" != "473" ]]; then
    echo "FAIL: readiness check failed (http_code=${code})" >&2
    exit 1
  fi
  echo "PASS: readiness check OK (${code})"
fi
