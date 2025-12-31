#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  gameday-vip-failover.sh --vip-group <dns|minio|shared> [--dry-run|--execute]

Safe VIP failover simulation using keepalived. Default is --dry-run.
Execution requires GAMEDAY_EXECUTE=1.
EOT
}

VIP_GROUP=""
MODE="dry-run"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vip-group)
      VIP_GROUP="${2:-}"
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

if [[ -z "${VIP_GROUP}" ]]; then
  echo "ERROR: --vip-group is required" >&2
  exit 2
fi

case "${VIP_GROUP}" in
  dns)
    VIP="192.168.11.100"
    EDGES=("192.168.11.111" "192.168.11.112")
    ;;
  minio)
    VIP="192.168.11.101"
    EDGES=("192.168.11.102" "192.168.11.103")
    ;;
  shared)
    VIP="192.168.11.122"
    EDGES=("192.168.11.106" "192.168.11.107")
    ;;
  *)
    echo "ERROR: invalid vip group: ${VIP_GROUP}" >&2
    exit 2
    ;;
 esac

ssh_user="${GAMEDAY_SSH_USER:-samakia}"

if [[ "${MODE}" == "dry-run" ]]; then
  echo "DRY-RUN: would evaluate VIP ${VIP} on ${EDGES[*]}"
  echo "DRY-RUN: would stop keepalived on current VIP holder and validate failover"
  echo "DRY-RUN: would start keepalived and confirm VIP stability"
  exit 0
fi

if [[ "${GAMEDAY_EXECUTE:-}" != "1" ]]; then
  echo "ERROR: execution requires GAMEDAY_EXECUTE=1" >&2
  exit 1
fi

owner=""
for host in "${EDGES[@]}"; do
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "${ssh_user}@${host}" "ip -o addr show" 2>/dev/null | grep -q "${VIP}"; then
    owner="${host}"
  fi
  done

if [[ -z "${owner}" ]]; then
  echo "ERROR: could not detect VIP owner for ${VIP}" >&2
  exit 1
fi

peer=""
for host in "${EDGES[@]}"; do
  if [[ "${host}" != "${owner}" ]]; then
    peer="${host}"
  fi
  done

if [[ -z "${peer}" ]]; then
  echo "ERROR: could not determine VIP peer" >&2
  exit 1
fi

echo "INFO: VIP ${VIP} owner=${owner} peer=${peer}"

ssh -o BatchMode=yes -o ConnectTimeout=5 "${ssh_user}@${owner}" "sudo -n systemctl stop keepalived"

sleep 5

if ssh -o BatchMode=yes -o ConnectTimeout=5 "${ssh_user}@${peer}" "ip -o addr show" 2>/dev/null | grep -q "${VIP}"; then
  echo "PASS: VIP moved to peer ${peer}"
else
  echo "FAIL: VIP did not move to peer ${peer}" >&2
  ssh -o BatchMode=yes -o ConnectTimeout=5 "${ssh_user}@${owner}" "sudo -n systemctl start keepalived" || true
  exit 1
fi

ssh -o BatchMode=yes -o ConnectTimeout=5 "${ssh_user}@${owner}" "sudo -n systemctl start keepalived"

echo "PASS: keepalived restarted on ${owner}"
