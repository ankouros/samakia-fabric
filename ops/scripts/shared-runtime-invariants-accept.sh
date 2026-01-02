#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"
ENV_CANONICAL="samakia-shared"

EDGE_1_LAN="192.168.11.106"
EDGE_2_LAN="192.168.11.107"

VAULT_1_VLAN="10.10.120.21"
VAULT_2_VLAN="10.10.120.22"
OBS_1_VLAN="10.10.120.31"
OBS_2_VLAN="10.10.120.32"

usage() {
  cat >&2 <<'EOT'
Usage:
  shared-runtime-invariants-accept.sh

Read-only runtime invariants acceptance for shared control-plane services.

Checks:
  - systemd units active + enabled
  - restart policy is configured (Restart != no)
  - non-interactive sudo is available for inspection
EOT
}

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "[FAIL] missing required command: $1" >&2; exit 1; }
}

ok() { echo "[OK] $*"; }
check() { echo "[CHECK] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o StrictHostKeyChecking=accept-new
  -o PasswordAuthentication=no
  -o LogLevel=ERROR
)

ssh_run() {
  local host="$1"; shift
  local jump="$1"; shift
  local args=("${SSH_OPTS[@]}")
  if [[ -n "${jump}" ]]; then
    args+=( -J "${jump}" )
  fi
  # shellcheck disable=SC2029
  ssh "${args[@]}" "samakia@${host}" "$@"
}

runtime_invariants_eval() {
  local active_ok="$1" enabled_ok="$2" restart_ok="$3"
  if [[ "${active_ok}" -eq 1 && "${enabled_ok}" -eq 1 && "${restart_ok}" -eq 1 ]]; then
    echo "PASS"
    return 0
  fi
  echo "FAIL"
  return 1
}

check_service() {
  local host="$1" jump="$2" svc="$3"

  check "${host}: ${svc}"

  if ! ssh_run "${host}" "${jump}" "sudo -n true" >/dev/null 2>&1; then
    fail "${host}: sudo -n unavailable; ensure samakia has passwordless sudo"
  fi

  local active enabled restart
  active="$(ssh_run "${host}" "${jump}" "sudo -n systemctl is-active ${svc} 2>/dev/null" || true)"
  enabled="$(ssh_run "${host}" "${jump}" "sudo -n systemctl is-enabled ${svc} 2>/dev/null" || true)"
  restart="$(ssh_run "${host}" "${jump}" "sudo -n systemctl show -p Restart ${svc} 2>/dev/null" || true)"
  restart="${restart#Restart=}"

  local active_ok=0 enabled_ok=0 restart_ok=0
  [[ "${active}" == "active" ]] && active_ok=1
  [[ "${enabled}" == "enabled" ]] && enabled_ok=1
  [[ "${restart}" != "no" && -n "${restart}" ]] && restart_ok=1

  if [[ "${active_ok}" -ne 1 ]]; then
    fail "${host}: ${svc} is not active (${active})"
  fi
  if [[ "${enabled_ok}" -ne 1 ]]; then
    fail "${host}: ${svc} is not enabled (${enabled})"
  fi
  if [[ "${restart_ok}" -ne 1 ]]; then
    fail "${host}: ${svc} restart policy is not set (Restart=${restart:-unknown})"
  fi

  ok "${host}: ${svc} active+enabled (Restart=${restart})"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  need ssh

  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
  fi

  if [[ -z "${ENV:-}" ]]; then
    fail "ENV is required (set ENV=${ENV_CANONICAL})"
  fi
  if [[ "${ENV}" != "${ENV_CANONICAL}" ]]; then
    fail "refusing to run: ENV=${ENV} (expected ENV=${ENV_CANONICAL})"
  fi

  local jump
  jump="samakia@${EDGE_1_LAN},samakia@${EDGE_2_LAN}"

  check "Shared edge services"
  for host in "${EDGE_1_LAN}" "${EDGE_2_LAN}"; do
    check_service "${host}" "" "chrony"
    check_service "${host}" "" "haproxy"
    check_service "${host}" "" "keepalived"
    check_service "${host}" "" "nftables"
  done

  check "Vault services"
  for host in "${VAULT_1_VLAN}" "${VAULT_2_VLAN}"; do
    check_service "${host}" "${jump}" "vault"
  done

  check "Observability services"
  obs_hosts=("${OBS_1_VLAN}" "${OBS_2_VLAN}")
  obs_services=("prometheus" "prometheus-alertmanager" "loki" "promtail" "grafana-server")
  for host in "${obs_hosts[@]}"; do
    for svc in "${obs_services[@]}"; do
      check_service "${host}" "${jump}" "${svc}"
    done
  done

  ok "Shared runtime invariants acceptance completed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
