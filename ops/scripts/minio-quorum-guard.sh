#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

MINIO_ENV_CANONICAL="samakia-minio"

MINIO_VIP="192.168.11.101"
MINIO_S3_PORT="9000"
MINIO_CONSOLE_PORT="9001"

MINIO_EDGE_1_CANONICAL="192.168.11.102"
MINIO_EDGE_2_CANONICAL="192.168.11.103"

MINIO_NODES_VLAN=("10.10.140.11" "10.10.140.12" "10.10.140.13")
MINIO_SDN_ZONE="zminio"
MINIO_SDN_VNET="vminio"
MINIO_SDN_SUBNET="10.10.140.0/24"
MINIO_SDN_GW="10.10.140.1"

RUNNER_ENV_FILE_DEFAULT="${HOME}/.config/samakia-fabric/env.sh"

usage() {
  cat >&2 <<EOF
Usage:
  minio-quorum-guard.sh [--force-env]

Detect-only guard that answers:
  "Is the MinIO backend safe enough for Terraform remote state writes?"

Outputs:
  - Compact stdout summary (secrets-safe)
  - Report written to: audit/minio-quorum-guard/<UTC>/report.md

Exit codes:
  0 = PASS (safe)
  2 = WARN (degraded; safe for reads only; block apply/migrate)
  1 = FAIL (unsafe; block)

Environment:
  ENV must be "${MINIO_ENV_CANONICAL}" unless --force-env is used.
  Runner env is consumed from ${RUNNER_ENV_FILE_DEFAULT} (if present) and/or exported vars.

Contracts:
  - Strict TLS (no insecure flags)
  - No infra mutation (detect-only)
  - No secrets printed
  - Repo-root deterministic paths via FABRIC_REPO_ROOT
EOF
}

log() { printf '%s\n' "$*" ; }
warn() { printf '[WARN] %s\n' "$*" >&2 ; }
ok() { printf '[OK] %s\n' "$*" ; }
check() { printf '[CHECK] %s\n' "$*" ; }
fail_line() { printf '[FAIL] %s\n' "$*" >&2 ; }

md() { printf '%s\n' "$*" >>"${REPORT_FILE}"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { fail_line "missing required command: $1"; return 1; }
}

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o StrictHostKeyChecking=yes
  -o PasswordAuthentication=no
  -o LogLevel=ERROR
)

ssh_run() {
  local host="$1"; shift
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "samakia@${host}" "$@"
}

read_hostvar_ansible_host() {
  local path="$1"
  awk -F': ' '$1=="ansible_host"{print $2; exit}' "$path" 2>/dev/null || true
}

curl_https_status() {
  local url="$1"
  curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "$url" 2>/dev/null || true
}

minio_guard_evaluate_signals() {
  local vip_tls_ok="$1" edge_ha_ok="$2" s3_liveness_ok="$3" sdn_ok="$4" quorum_ok="$5" backends_ok="$6" admin_ok="$7"

  if [[ "${vip_tls_ok}" != "1" || "${edge_ha_ok}" != "1" || "${s3_liveness_ok}" != "1" || "${sdn_ok}" != "1" || "${quorum_ok}" != "1" ]]; then
    echo "FAIL"
    return 1
  fi
  if [[ "${backends_ok}" != "1" || "${admin_ok}" != "1" ]]; then
    echo "WARN"
    return 2
  fi
  echo "PASS"
  return 0
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local force_env=0
  if [[ "${1:-}" == "--force-env" ]]; then
    force_env=1
    shift
  fi

  if [[ -z "${ENV:-}" ]]; then
    fail_line "ENV is required (set ENV=${MINIO_ENV_CANONICAL})"
    exit 2
  fi
  if [[ "${ENV}" != "${MINIO_ENV_CANONICAL}" && "${force_env}" -ne 1 ]]; then
    fail_line "refusing to run: ENV=${ENV} (expected ENV=${MINIO_ENV_CANONICAL}). Use --force-env only for debugging."
    exit 2
  fi

  # Best-effort load runner env file (does not print secrets).
  if [[ -f "${RUNNER_ENV_FILE_DEFAULT}" ]]; then
    # shellcheck disable=SC1090
    source "${RUNNER_ENV_FILE_DEFAULT}"
  fi

  local ts report_dir
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  report_dir="${FABRIC_REPO_ROOT}/audit/minio-quorum-guard/${ts}"
  mkdir -p "${report_dir}"
  chmod 700 "${report_dir}" 2>/dev/null || true
  REPORT_FILE="${report_dir}/report.md"
  : >"${REPORT_FILE}"

  md "# MinIO quorum guard report"
  md ""
  md "- Timestamp (UTC): \`${ts}\`"
  md "- ENV: \`${ENV}\`"
  md "- VIP: \`${MINIO_VIP}\` (S3 \`${MINIO_S3_PORT}\`, console \`${MINIO_CONSOLE_PORT}\`)"
  md "- SDN: zone=\`${MINIO_SDN_ZONE}\` vnet=\`${MINIO_SDN_VNET}\` subnet=\`${MINIO_SDN_SUBNET}\` gw=\`${MINIO_SDN_GW}\`"
  md ""

  require_cmd bash || exit 1
  require_cmd curl || exit 1
  require_cmd python3 || exit 1
  require_cmd ssh || exit 1

  local fail_reasons=()
  local warn_reasons=()

  check "Runner prerequisites (presence-only; secrets not printed)"
  if ! bash "${FABRIC_REPO_ROOT}/ops/scripts/runner-env-check.sh" --file "${RUNNER_ENV_FILE_DEFAULT}" >/dev/null 2>&1; then
    fail_reasons+=("runner env check failed (missing vars and/or CA trust); run: make backend.configure && make runner.env.check")
    fail_line "runner env check failed (run: make backend.configure && make runner.env.check)"
  else
    ok "runner env check OK"
  fi

  md "## Checks"
  md ""

  #############################################################################
  # E) SDN plane sanity (read-only)
  #############################################################################
  check "SDN plane sanity (read-only check-only)"
  if bash "${FABRIC_REPO_ROOT}/ops/scripts/proxmox-sdn-ensure-stateful-plane.sh" --check-only >/dev/null 2>&1; then
    ok "SDN plane present and matches contract"
    md "- SDN plane: OK (present and matches contract)"
    sdn_ok=1
  else
    fail_reasons+=("SDN plane check failed: ensure zminio/vminio/VLAN140/subnet/gateway exist and match contract")
    fail_line "SDN plane check failed (zminio/vminio/VLAN140 not present or mismatch)"
    md "- SDN plane: FAIL (missing or mismatch; requires operator action or token perms)"
    sdn_ok=0
  fi

  #############################################################################
  # A) VIP reachability + strict TLS (runner)
  #############################################################################
  check "VIP TLS reachability (strict TLS)"
  vip_live_code="$(curl_https_status "https://${MINIO_VIP}:${MINIO_S3_PORT}/minio/health/live")"
  vip_cluster_code="$(curl_https_status "https://${MINIO_VIP}:${MINIO_S3_PORT}/minio/health/cluster")"
  console_code="$(curl_https_status "https://${MINIO_VIP}:${MINIO_CONSOLE_PORT}/")"

  md ""
  md "### VIP endpoints"
  md ""
  md "- \`https://${MINIO_VIP}:${MINIO_S3_PORT}/minio/health/live\` → HTTP \`${vip_live_code:-}\`"
  md "- \`https://${MINIO_VIP}:${MINIO_S3_PORT}/minio/health/cluster\` → HTTP \`${vip_cluster_code:-}\`"
  md "- \`https://${MINIO_VIP}:${MINIO_CONSOLE_PORT}/\` → HTTP \`${console_code:-}\`"

  vip_tls_ok=1
  if [[ "${vip_live_code}" != "200" ]]; then
    vip_tls_ok=0
    fail_reasons+=("VIP health/live failed over strict TLS (check VIP owner, HAProxy, cert chain)")
  fi
  if [[ "${console_code}" != "200" && "${console_code}" != "302" && "${console_code}" != "301" ]]; then
    vip_tls_ok=0
    fail_reasons+=("VIP console endpoint failed over strict TLS (check HAProxy bind/cert)")
  fi
  if [[ "${vip_tls_ok}" -eq 1 ]]; then
    ok "VIP endpoints reachable over strict TLS"
  else
    fail_line "VIP endpoints not reachable over strict TLS"
  fi

  #############################################################################
  # D) Edge HA front door sanity (via SSH)
  #############################################################################
  edge1_hostvar="${FABRIC_REPO_ROOT}/fabric-core/ansible/host_vars/minio-edge-1.yml"
  edge2_hostvar="${FABRIC_REPO_ROOT}/fabric-core/ansible/host_vars/minio-edge-2.yml"
  edge1_lan="$(read_hostvar_ansible_host "${edge1_hostvar}")"
  edge2_lan="$(read_hostvar_ansible_host "${edge2_hostvar}")"

  md ""
  md "### Edge HA sanity"
  md ""
  md "- Expected mgmt IPs: edge-1=\`${MINIO_EDGE_1_CANONICAL}\`, edge-2=\`${MINIO_EDGE_2_CANONICAL}\`"
  md "- host_vars mgmt IPs: edge-1=\`${edge1_lan:-missing}\`, edge-2=\`${edge2_lan:-missing}\`"

  edge_ha_ok=1
  if [[ -z "${edge1_lan}" || -z "${edge2_lan}" ]]; then
    edge_ha_ok=0
    fail_reasons+=("minio-edge host_vars missing ansible_host; cannot validate HA")
  fi

  if [[ "${edge1_lan:-}" != "${MINIO_EDGE_1_CANONICAL}" || "${edge2_lan:-}" != "${MINIO_EDGE_2_CANONICAL}" ]]; then
    edge_ha_ok=0
    fail_reasons+=("minio-edge mgmt IPs do not match canonical contract (.102/.103); update Terraform+host_vars to match and avoid LAN collision")
  fi

  if [[ "${edge_ha_ok}" -eq 1 ]]; then
    check "Edge services active (keepalived + haproxy)"
    for host in "${edge1_lan}" "${edge2_lan}"; do
      if ! ssh_run "${host}" "sudo -n systemctl is-active --quiet keepalived"; then
        edge_ha_ok=0
        fail_reasons+=("keepalived not active on edge ${host}")
      fi
      if ! ssh_run "${host}" "sudo -n systemctl is-active --quiet haproxy"; then
        edge_ha_ok=0
        fail_reasons+=("haproxy not active on edge ${host}")
      fi
    done
    if [[ "${edge_ha_ok}" -eq 1 ]]; then
      ok "keepalived + haproxy active on both edges"
      md "- systemd keepalived/haproxy: OK on both edges"
    else
      fail_line "edge services are not healthy (keepalived/haproxy)"
      md "- systemd keepalived/haproxy: FAIL (see stderr)"
    fi

    check "Exactly one VIP owner (no split ownership)"
    vip_holders=0
    active_edge=""
    for host in "${edge1_lan}" "${edge2_lan}"; do
      if ssh_run "${host}" "ip -4 addr show | grep -q \"${MINIO_VIP}/\""; then
        vip_holders=$((vip_holders + 1))
        active_edge="${host}"
      fi
    done
    md "- VIP ownership count for \`${MINIO_VIP}\`: \`${vip_holders}\`"
    if [[ "${vip_holders}" -ne 1 ]]; then
      edge_ha_ok=0
      fail_reasons+=("expected exactly one VIP owner for ${MINIO_VIP}; got ${vip_holders} (split-brain risk)")
      fail_line "expected exactly one VIP owner for ${MINIO_VIP}; got ${vip_holders}"
    else
      ok "exactly one edge owns VIP (active=${active_edge})"
      md "- VIP owner: \`${active_edge}\`"
    fi

    check "VIP reachable from both edges (consistency proxy)"
    for host in "${edge1_lan}" "${edge2_lan}"; do
      if ! ssh_run "${host}" "curl -fsS \"https://${MINIO_VIP}:${MINIO_S3_PORT}/minio/health/live\" >/dev/null"; then
        edge_ha_ok=0
        fail_reasons+=("VIP not reachable from edge ${host} (routing/NAT/HAProxy issue)")
      fi
    done
    if [[ "${edge_ha_ok}" -eq 1 ]]; then
      ok "VIP reachable from both edges"
      md "- VIP reachable from both edges: OK"
    else
      fail_line "VIP not reachable from one or both edges"
      md "- VIP reachable from both edges: FAIL"
    fi
  else
    fail_line "edge HA sanity cannot be validated (host_vars mismatch or missing)"
  fi

  #############################################################################
  # B) Backend API liveness (read-only) via edge mc aliases
  #############################################################################
  s3_liveness_ok=0
  bucket="${TF_BACKEND_S3_BUCKET:-}"
  md ""
  md "### Backend API liveness (read-only)"
  md ""
  md "- TF_BACKEND_S3_BUCKET: \`${bucket:-missing}\`"

  if [[ -z "${bucket}" ]]; then
    fail_reasons+=("TF_BACKEND_S3_BUCKET is missing; run: make backend.configure")
    fail_line "TF_BACKEND_S3_BUCKET is missing (run: make backend.configure)"
  elif [[ -n "${active_edge:-}" && "${edge_ha_ok}" -eq 1 ]]; then
    check "S3 bucket list via edge mc alias (terraform user)"
    if ssh_run "${active_edge}" "sudo -n /usr/local/bin/mc ls \"samakia-tf/${bucket}\" >/dev/null"; then
      ok "terraform user can list bucket via edge mc alias"
      md "- mc ls samakia-tf/${bucket}: OK (via active edge)"
      s3_liveness_ok=1
    else
      fail_reasons+=("terraform user cannot list bucket via edge mc alias (ensure state-backend.yml applied and creds exist)")
      fail_line "terraform user cannot list bucket via edge mc alias"
      md "- mc ls samakia-tf/${bucket}: FAIL"
    fi
  else
    fail_reasons+=("cannot run bucket liveness check (no active edge / edge HA not healthy)")
    fail_line "cannot run bucket liveness check (no active edge / edge HA not healthy)"
  fi

  #############################################################################
  # C) Quorum / erasure health (read-only)
  #############################################################################
  quorum_ok=0
  backends_ok=0
  admin_ok=0

  if [[ "${vip_cluster_code}" == "200" ]]; then
    quorum_ok=1
    ok "cluster health endpoint indicates quorum is present (/minio/health/cluster)"
    md ""
    md "### Quorum / erasure health"
    md ""
    md "- /minio/health/cluster: OK (HTTP 200)"
  else
    fail_reasons+=("cluster health endpoint indicates quorum risk (/minio/health/cluster != 200)")
    fail_line "cluster health endpoint indicates quorum risk (/minio/health/cluster != 200)"
    md ""
    md "### Quorum / erasure health"
    md ""
    md "- /minio/health/cluster: FAIL (HTTP ${vip_cluster_code:-})"
  fi

  if [[ -n "${active_edge:-}" && "${edge_ha_ok}" -eq 1 ]]; then
    check "MinIO backend nodes health via active edge (HAProxy backend reachability)"
    backend_fail=0
    for ip in "${MINIO_NODES_VLAN[@]}"; do
      if ! ssh_run "${active_edge}" "curl -fsS \"http://${ip}:${MINIO_S3_PORT}/minio/health/live\" >/dev/null"; then
        backend_fail=1
        warn_reasons+=("minio backend health failed via at least one node (ip=${ip})")
      fi
      if ! ssh_run "${active_edge}" "curl -fsS -o /dev/null -I \"http://${ip}:${MINIO_CONSOLE_PORT}/\""; then
        backend_fail=1
        warn_reasons+=("minio console backend not reachable via at least one node (ip=${ip})")
      fi
    done
    if [[ "${backend_fail}" -eq 0 ]]; then
      ok "all backends reachable via active edge"
      md "- Backends reachable via active edge: OK (3/3)"
      backends_ok=1
    else
      warn "one or more backends are not reachable via active edge (degraded)"
      md "- Backends reachable via active edge: WARN (degraded)"
      backends_ok=0
    fi

    check "mc admin info (root alias) signals (best-effort)"
    set +e
    admin_parse_out="$(
      ssh_run "${active_edge}" "sudo -n /usr/local/bin/mc admin info samakia-root --json" 2>/dev/null | \
        python3 -c '
import json
import sys

objs = []
for line in sys.stdin:
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        objs.append(json.loads(line))
    except Exception:
        pass

if not objs:
    print("PARSE_ERROR:no_json")
    sys.exit(2)

o = objs[-1]
info = o.get("info", {}) if isinstance(o, dict) else {}
backend = info.get("backend", {}) if isinstance(info, dict) else {}
servers = info.get("servers", []) if isinstance(info, dict) else []

backend_type = str(backend.get("backendType", ""))
online_disks = backend.get("onlineDisks")
offline_disks = backend.get("offlineDisks")

def _as_int(v):
    if isinstance(v, int):
        return v
    if isinstance(v, str) and v.isdigit():
        return int(v)
    return None

bad = []
if backend_type.lower() != "erasure":
    bad.append("backendType=" + (backend_type or "missing"))

if not isinstance(servers, list) or len(servers) != 3:
    bad.append("servers=" + (str(len(servers)) if isinstance(servers, list) else "missing"))
else:
    states = [str(s.get("state", "")) for s in servers if isinstance(s, dict)]
    if len(states) != 3 or any(st.lower() != "online" for st in states):
        bad.append("server_state")

od = _as_int(online_disks)
fd = _as_int(offline_disks)
if od is None or od < 6:
    bad.append(f"onlineDisks={online_disks!r}")
if fd is None or fd != 0:
    bad.append(f"offlineDisks={offline_disks!r}")

if bad:
    print("BAD_SIGNALS:" + ",".join(bad))
    sys.exit(2)

print("OK")
sys.exit(0)
        '
    )"
    rc=$?
    set -e
    if [[ -n "${admin_parse_out}" ]]; then
      printf '%s\n' "${admin_parse_out}"
    fi
    if [[ "${rc}" -eq 0 ]]; then
      ok "mc admin info indicates erasure mode, 3 online servers, 0 offline disks"
      md "- mc admin info: OK (erasure, 3 online servers, 0 offline disks)"
      admin_ok=1
    else
      warn_reasons+=("mc admin info indicates degraded/unparseable state (cannot confirm 3 online servers / 0 offline disks)")
      warn "mc admin info indicates degraded/unparseable state (WARN; blocks writes)"
      md "- mc admin info: WARN (degraded/unparseable)"
      admin_ok=0
    fi
  else
    warn_reasons+=("cannot validate backend reachability/admin signals (edge HA not healthy)")
  fi

  #############################################################################
  # Decision
  #############################################################################
  set +e
  result="$(minio_guard_evaluate_signals "${vip_tls_ok}" "${edge_ha_ok}" "${s3_liveness_ok}" "${sdn_ok}" "${quorum_ok}" "${backends_ok}" "${admin_ok}")"
  rc=$?
  set -e

  md ""
  md "## Decision"
  md ""
  md "- Result: \`${result}\`"

  if ((${#fail_reasons[@]} > 0)); then
    md ""
    md "### Fail reasons"
    for r in "${fail_reasons[@]}"; do
      md "- ${r}"
    done
  fi
  if ((${#warn_reasons[@]} > 0)); then
    md ""
    md "### Warn reasons"
    for r in "${warn_reasons[@]}"; do
      md "- ${r}"
    done
  fi

  md ""
  md "## Remediation (operator guidance)"
  md ""
  md "- If TLS fails: re-run \`make backend.configure\` to install backend CA into runner trust store; verify with \`make runner.env.check\`."
  md "- If SDN check fails: create/repair zminio/vminio/VLAN140 plane (must match contract) and ensure the Proxmox token can read SDN primitives."
  md "- If edge SSH fails: fix allowlist + known_hosts (see \`make ssh.trust.rotate HOST=<edge-ip>\`), then re-run the guard."
  md "- If quorum/health endpoints fail: restore MinIO cluster health before any Terraform state writes or migrations."

  log ""
  log "=== MinIO quorum guard: ${result} ==="
  log "Report: ${REPORT_FILE}"

  exit "${rc}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
