#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"
OBS_VIP="192.168.11.122"
CA_DEFAULT="${HOME}/.config/samakia-fabric/pki/shared-bootstrap-ca.crt"

usage() {
  cat >&2 <<'EOT'
Usage:
  shared-obs-ingest-accept.sh

Read-only observability ingestion acceptance.

Checks:
  - Loki is reachable over TLS
  - At least one deterministic log source is queryable in Loki
    (systemd-journal or /var/log/*log)
EOT
}

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "[FAIL] missing required command: $1" >&2; exit 1; }
}

ok() { echo "[OK] $*"; }
check() { echo "[CHECK] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

obs_ingest_series_count() {
  local json_file="$1"
  python3 - "$json_file" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        data = json.load(fh)
    series = data.get("data", [])
    if isinstance(series, list):
        print(len(series))
    else:
        print(0)
except Exception:
    print(0)
PY
}

fetch_series() {
  local selector_encoded="$1"
  local dest="$2"
  local url
  url="https://${OBS_VIP}:3100/loki/api/v1/series?match[]=${selector_encoded}"
  curl --cacert "${ca_path}" -fsS --max-time 8 "${url}" -o "${dest}"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  need curl
  need python3

  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
  fi

  ca_path="${OBS_CA_SRC:-${SHARED_EDGE_CA_SRC:-${CA_DEFAULT}}}"
  if [[ ! -f "${ca_path}" ]]; then
    fail "shared CA not found: ${ca_path} (run shared PKI setup first)"
  fi

  check "Query Loki series via VIP ${OBS_VIP}"

  local selector_journal selector_varlogs
  selector_journal="%7Bjob%3D%22systemd-journal%22%7D"
  selector_varlogs="%7Bjob%3D%22varlogs%22%7D"

  local attempts=6
  local delay=5
  local found=0
  local source=""

  for ((i=1; i<=attempts; i++)); do
    local tmp_journal tmp_varlogs
    tmp_journal="$(mktemp)"
    tmp_varlogs="$(mktemp)"

    if fetch_series "${selector_journal}" "${tmp_journal}"; then
      local count_journal
      count_journal="$(obs_ingest_series_count "${tmp_journal}")"
      if [[ "${count_journal}" -gt 0 ]]; then
        found=1
        source="systemd-journal"
      fi
    fi

    if [[ "${found}" -eq 0 ]]; then
      if fetch_series "${selector_varlogs}" "${tmp_varlogs}"; then
        local count_varlogs
        count_varlogs="$(obs_ingest_series_count "${tmp_varlogs}")"
        if [[ "${count_varlogs}" -gt 0 ]]; then
          found=1
          source="varlogs"
        fi
      fi
    fi

    rm -f "${tmp_journal}" "${tmp_varlogs}"

    if [[ "${found}" -eq 1 ]]; then
      break
    fi

    sleep "${delay}"
  done

  if [[ "${found}" -ne 1 ]]; then
    fail "Loki ingestion not confirmed (no series for systemd-journal or varlogs)"
  fi

  ok "Loki ingestion confirmed (source=${source})"
  ok "Shared observability ingestion acceptance completed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
