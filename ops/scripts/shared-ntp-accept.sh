#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"

NTP_VIP="192.168.11.120"
EDGE_1="192.168.11.106"
EDGE_2="192.168.11.107"

usage() {
  cat >&2 <<'EOF'
Usage:
  shared-ntp-accept.sh

Read-only NTP acceptance tests for the shared control plane.

Checks:
  - chrony active on both ntp nodes
  - exactly one edge holds the NTP VIP
  - NTP service listening on UDP/123 on VIP holder
  - chrony has at least one reachable upstream source (best-effort)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "[FAIL] missing required command: $1" >&2; exit 1; }
}

need ssh
need grep
need awk

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

ok() { echo "[OK] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

ssh_run() {
  local host="$1"
  shift
  ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "samakia@${host}" "$@"
}

for host in "${EDGE_1}" "${EDGE_2}"; do
  ssh_run "${host}" "systemctl is-active --quiet chrony" || fail "chrony not active on ${host}"
  ok "chrony active on ${host}"

done

vip_holders=0
active_edge=""
for host in "${EDGE_1}" "${EDGE_2}"; do
  if ssh_run "${host}" "ip -4 addr show | grep -q '${NTP_VIP}/'"; then
    vip_holders=$((vip_holders + 1))
    active_edge="${host}"
  fi

done
if [[ "${vip_holders}" -ne 1 ]]; then
  fail "expected exactly one edge holds NTP VIP ${NTP_VIP}; got ${vip_holders}"
fi
ok "exactly one edge holds NTP VIP ${NTP_VIP} (active=${active_edge})"

ssh_run "${active_edge}" "ss -lun | grep -q ':123'" || fail "NTP UDP/123 not listening on active edge"
ok "NTP UDP/123 listening on active edge"

sources_ok=0
for host in "${EDGE_1}" "${EDGE_2}"; do
  if ssh_run "${host}" "chronyc -n sources" | grep -Eq '^\^\*|^\^\+'; then
    sources_ok=1
  fi

done
if [[ "${sources_ok}" -ne 1 ]]; then
  fail "chrony has no reachable upstream sources (best-effort)"
fi
ok "chrony has reachable upstream source(s) (best-effort)"

ok "Shared NTP acceptance completed"
