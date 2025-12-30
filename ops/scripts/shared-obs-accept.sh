#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"
OBS_VIP="192.168.11.122"
CA_DEFAULT="${HOME}/.config/samakia-fabric/pki/shared-bootstrap-ca.crt"

usage() {
  cat >&2 <<'EOF'
Usage:
  shared-obs-accept.sh

Read-only observability acceptance tests for shared control plane.

Checks:
  - Grafana reachable over TLS
  - Prometheus reachable over TLS
  - Alertmanager reachable over TLS
  - Loki reachable over TLS
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "[FAIL] missing required command: $1" >&2; exit 1; }
}

need curl

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

ca_path="${OBS_CA_SRC:-${SHARED_EDGE_CA_SRC:-${CA_DEFAULT}}}"
if [[ ! -f "${ca_path}" ]]; then
  echo "[FAIL] shared CA not found: ${ca_path} (run shared PKI setup first)" >&2
  exit 1
fi

ok() { echo "[OK] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

check_http() {
  local url="$1"
  local name="$2"
  local code
  code="$(curl --cacert "${ca_path}" -sS -o /dev/null -w '%{http_code}' "${url}" || true)"
  if [[ "${code}" != "200" && "${code}" != "302" && "${code}" != "307" ]]; then
    fail "${name} unexpected HTTP code: ${code} (${url})"
  fi
  ok "${name} reachable (http_code=${code})"
}

check_http "https://${OBS_VIP}:3000/" "Grafana"
check_http "https://${OBS_VIP}:9090/-/healthy" "Prometheus"
check_http "https://${OBS_VIP}:9093/-/ready" "Alertmanager"
check_http "https://${OBS_VIP}:3100/ready" "Loki"

ok "Shared observability acceptance completed"
