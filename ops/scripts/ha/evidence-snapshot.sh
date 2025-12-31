#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ENV_FILE="${HOME}/.config/samakia-fabric/env.sh"
CA_DEFAULT="${HOME}/.config/samakia-fabric/pki/shared-bootstrap-ca.crt"

api_url="${TF_VAR_pm_api_url:-${PM_API_URL:-}}"
token_id="${TF_VAR_pm_api_token_id:-${PM_API_TOKEN_ID:-}}"
token_secret="${TF_VAR_pm_api_token_secret:-${PM_API_TOKEN_SECRET:-}}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

api_url="${TF_VAR_pm_api_url:-${PM_API_URL:-${api_url}}}"
token_id="${TF_VAR_pm_api_token_id:-${PM_API_TOKEN_ID:-${token_id}}}"
token_secret="${TF_VAR_pm_api_token_secret:-${PM_API_TOKEN_SECRET:-${token_secret}}}"

if [[ -z "${api_url}" || -z "${token_id}" || -z "${token_secret}" ]]; then
  echo "ERROR: missing Proxmox API env vars (TF_VAR_pm_api_url/TF_VAR_pm_api_token_id/TF_VAR_pm_api_token_secret)." >&2
  exit 1
fi

if [[ "${token_id}" != *"!"* ]]; then
  echo "ERROR: Proxmox token id must include '!': ${token_id}" >&2
  exit 1
fi

ca_path="${OBS_CA_SRC:-${SHARED_EDGE_CA_SRC:-${CA_DEFAULT}}}"
if [[ ! -f "${ca_path}" ]]; then
  echo "ERROR: shared CA not found: ${ca_path}" >&2
  exit 1
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="${FABRIC_REPO_ROOT}/artifacts/ha-evidence/${stamp}"
mkdir -p "${out_dir}"
report="${out_dir}/report.md"
ssh_user="${HA_SSH_USER:-samakia}"

header="Authorization: PVEAPIToken=${token_id}=${token_secret}"

log() { echo "$*" | tee -a "${report}"; }
failure=0

log "# HA Evidence Snapshot"
log ""
log "Timestamp (UTC): ${stamp}"
log "Repo root: ${FABRIC_REPO_ROOT}"
log ""

log "## Proxmox Cluster Status"
cluster_json="$(curl -fsS -H "${header}" "${api_url%/}/cluster/status" || true)"
if [[ -z "${cluster_json}" ]]; then
  log "cluster_status=ERROR (empty response)"
  failure=1
else
  tmp_cluster="$(mktemp)"
  tmp_cluster_out="$(mktemp)"
  printf '%s' "${cluster_json}" > "${tmp_cluster}"
  if python3 - "${tmp_cluster}" > "${tmp_cluster_out}" <<'PY'; then
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    payload = json.load(fh)
entries = payload.get("data", []) or []
quorum = None
nodes = []
for item in entries:
    if item.get("type") == "cluster":
        quorum = item.get("quorate")
    if item.get("type") == "node":
        nodes.append((item.get("name"), item.get("online")))
print(f"quorate={quorum}")
for name, online in nodes:
    print(f"node={name} online={online}")
PY
    tee -a "${report}" < "${tmp_cluster_out}"
  else
    failure=1
  fi
  rm -f "${tmp_cluster}" "${tmp_cluster_out}"
fi
log ""

log "## VIP Ownership"
check_vip() {
  local vip="$1"
  shift
  local owners=()
  for host in "$@"; do
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${ssh_user}@${host}" "ip -o addr show" 2>/dev/null | grep -q "${vip}"; then
      owners+=("${host}")
    fi
  done
  if [[ "${#owners[@]}" -eq 0 ]]; then
    log "- ${vip}: owner=NONE"
    return 1
  fi
  log "- ${vip}: owner=${owners[*]}"
  if [[ "${#owners[@]}" -gt 1 ]]; then
    return 1
  fi
  return 0
}

check_vip "192.168.11.100" 192.168.11.111 192.168.11.112 || failure=1
check_vip "192.168.11.101" 192.168.11.102 192.168.11.103 || failure=1
check_vip "192.168.11.120" 192.168.11.106 192.168.11.107 || failure=1
check_vip "192.168.11.121" 192.168.11.106 192.168.11.107 || failure=1
check_vip "192.168.11.122" 192.168.11.106 192.168.11.107 || failure=1
log ""

log "## Service Readiness"
readiness_check() {
  local name="$1"
  local url="$2"
  local allow="$3"
  local code
  code=$(curl --cacert "${ca_path}" -sS -o /dev/null -w "%{http_code}" "${url}" || true)
  log "- ${name}: ${url} http_code=${code}"
  if [[ "${allow}" != *"${code}"* ]]; then
    failure=1
  fi
}

readiness_check "vault" "https://192.168.11.121:8200/v1/sys/health" "200 429 472 473"
readiness_check "grafana" "https://192.168.11.122:3000/" "200 302"
readiness_check "prometheus" "https://192.168.11.122:9090/-/ready" "200"
readiness_check "alertmanager" "https://192.168.11.122:9093/-/ready" "200"
readiness_check "loki" "https://192.168.11.122:3100/ready" "200"
log ""

log "## Loki Ingestion Check"
if bash "${FABRIC_REPO_ROOT}/ops/scripts/shared-obs-ingest-accept.sh" >/dev/null; then
  log "- Loki ingestion: PASS"
else
  log "- Loki ingestion: FAIL"
  failure=1
fi
log ""

log "## SDN Stability"
pending_value=""
sdn_payload="$(curl -fsS -H "${header}" "${api_url%/}/cluster/sdn" || true)"
if [[ -z "${sdn_payload}" ]]; then
  log "- SDN pending status: ERROR (empty response)"
  failure=1
else
  tmp_sdn="$(mktemp)"
  printf '%s' "${sdn_payload}" > "${tmp_sdn}"
  pending_value="$(python3 -c 'import json,sys; data=json.load(open(sys.argv[1],"r",encoding="utf-8")); print(data.get("pending"))' "${tmp_sdn}" 2>/dev/null || true)"
  if [[ -n "${pending_value}" ]]; then
    log "- SDN pending status: ${pending_value}"
    if [[ "${pending_value}" != "False" && "${pending_value}" != "false" && "${pending_value}" != "0" && "${pending_value}" != "" && "${pending_value}" != "None" ]]; then
      failure=1
    fi
  else
    log "- SDN pending status: FAIL"
    failure=1
  fi
  rm -f "${tmp_sdn}"
fi

log ""
log "Snapshot complete: ${report}"
if [[ "${failure}" -ne 0 ]]; then
  echo "ERROR: evidence snapshot detected failing signals (see report)." >&2
  exit 1
fi
