#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


MINIO_ENV_CANONICAL="samakia-minio"

MINIO_VIP="192.168.11.101"
MINIO_S3_PORT="9000"
MINIO_CONSOLE_PORT="9001"

MINIO_EDGE_1_CANONICAL="192.168.11.102"
MINIO_EDGE_2_CANONICAL="192.168.11.103"

RUNNER_ENV_FILE_DEFAULT="${HOME}/.config/samakia-fabric/env.sh"

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o StrictHostKeyChecking=yes
  -o PasswordAuthentication=no
  -o LogLevel=ERROR
)

usage() {
  cat >&2 <<EOF
Usage:
  minio-edge-failure-sim.sh

Inputs:
  ENV=${MINIO_ENV_CANONICAL} (required)
  EDGE=minio-edge-1|minio-edge-2 (required)

Simulation (reversible, non-destructive):
  - Stops keepalived + haproxy on the selected edge only
  - Verifies VIP failover behavior and VIP availability
  - Restores services and re-verifies steady state

Contracts:
  - Strict TLS (no insecure flags)
  - No Terraform state changes
  - No Proxmox node SSH/SCP
  - SSH only to minio edges via mgmt IPs with strict host key checking
  - Secrets not printed

Report:
  audit/minio-edge-failure-sim/<UTC>/report.md
EOF
}

log() { printf '%s\n' "$*"; }
pre() { printf '[PRE] %s\n' "$*"; }
check() { printf '[CHECK] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; }
inj() { printf '[FAILURE] %s\n' "$*"; }
rec() { printf '[RECOVER] %s\n' "$*"; }

md() { printf '%s\n' "$*" >>"${REPORT_FILE}"; }

ssh_run() {
  local host="$1"; shift
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "samakia@${host}" "$@"
}

read_hostvar_ansible_host() {
  local path="$1"
  awk -F': ' '$1=="ansible_host"{print $2; exit}' "$path" 2>/dev/null || true
}

curl_https_ok() {
  local url="$1"
  curl -fsS --max-time 8 "$url" >/dev/null 2>&1
}

systemd_active() {
  local host="$1" unit="$2"
  ssh_run "$host" "sudo -n systemctl is-active --quiet ${unit}"
}

vip_holders_count() {
  local host_a="$1" host_b="$2"
  local c=0
  if ssh_run "$host_a" "ip -4 addr show | grep -q \"${MINIO_VIP}/\""; then c=$((c+1)); fi
  if ssh_run "$host_b" "ip -4 addr show | grep -q \"${MINIO_VIP}/\""; then c=$((c+1)); fi
  echo "$c"
}

vip_owner() {
  local host_a="$1" host_b="$2"
  if ssh_run "$host_a" "ip -4 addr show | grep -q \"${MINIO_VIP}/\""; then echo "$host_a"; return 0; fi
  if ssh_run "$host_b" "ip -4 addr show | grep -q \"${MINIO_VIP}/\""; then echo "$host_b"; return 0; fi
  echo ""
  return 1
}

wait_vip_owner() {
  local expect_host="$1" host_a="$2" host_b="$3" timeout_s="${4:-45}"
  local start now owner
  start="$(date +%s)"
  while true; do
    owner="$(vip_owner "$host_a" "$host_b" || true)"
    if [[ -n "${owner}" && "${owner}" == "${expect_host}" ]]; then
      echo "${owner}"
      return 0
    fi
    now="$(date +%s)"
    if (( now - start >= timeout_s )); then
      echo "${owner}"
      return 1
    fi
    sleep 1
  done
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

if [[ -z "${ENV:-}" ]]; then
  fail "ENV is required (set ENV=${MINIO_ENV_CANONICAL})"
  exit 2
fi
if [[ "${ENV}" != "${MINIO_ENV_CANONICAL}" ]]; then
  fail "refusing to run: ENV=${ENV} (expected ENV=${MINIO_ENV_CANONICAL})"
  exit 2
fi
if [[ -z "${EDGE:-}" ]]; then
  fail "EDGE is required (EDGE=minio-edge-1|minio-edge-2)"
  exit 2
fi
if [[ "${EDGE}" != "minio-edge-1" && "${EDGE}" != "minio-edge-2" ]]; then
  fail "invalid EDGE=${EDGE} (expected minio-edge-1|minio-edge-2)"
  exit 2
fi

  # Best-effort load runner env file (does not print secrets).
  if [[ -f "${RUNNER_ENV_FILE_DEFAULT}" ]]; then
    # shellcheck disable=SC1090
    source "${RUNNER_ENV_FILE_DEFAULT}"
  fi

  local ts report_dir
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  report_dir="${FABRIC_REPO_ROOT}/audit/minio-edge-failure-sim/${ts}"
  mkdir -p "${report_dir}"
  chmod 700 "${report_dir}" 2>/dev/null || true
  REPORT_FILE="${report_dir}/report.md"
  : >"${REPORT_FILE}"

  md "# MinIO edge failure simulation report"
  md ""
  md "- Timestamp (UTC): \`${ts}\`"
  md "- ENV: \`${ENV}\`"
  md "- EDGE (faulted): \`${EDGE}\`"
  md "- VIP: \`${MINIO_VIP}\` (S3 \`${MINIO_S3_PORT}\`, console \`${MINIO_CONSOLE_PORT}\`)"
  md ""

  pre "Runner env check (presence-only; secrets not printed)"
  if ! bash "${FABRIC_REPO_ROOT}/ops/scripts/runner-env-check.sh" --file "${RUNNER_ENV_FILE_DEFAULT}" >/dev/null; then
    fail "runner env check failed; run: make backend.configure && make runner.env.check"
    md "Result: FAIL (runner env check failed)"
    md "Report: ${REPORT_FILE}"
    exit 1
  fi
  ok "runner env check OK"

  local edge1_hv edge2_hv edge1_lan edge2_lan victim survivor
  edge1_hv="${FABRIC_REPO_ROOT}/fabric-core/ansible/host_vars/minio-edge-1.yml"
  edge2_hv="${FABRIC_REPO_ROOT}/fabric-core/ansible/host_vars/minio-edge-2.yml"
  edge1_lan="$(read_hostvar_ansible_host "${edge1_hv}")"
  edge2_lan="$(read_hostvar_ansible_host "${edge2_hv}")"

  md "## Inputs"
  md ""
  md "- host_vars edge-1 ansible_host: \`${edge1_lan:-missing}\` (expected \`${MINIO_EDGE_1_CANONICAL}\`)"
  md "- host_vars edge-2 ansible_host: \`${edge2_lan:-missing}\` (expected \`${MINIO_EDGE_2_CANONICAL}\`)"

  pre "Validate canonical edge mgmt IP contract (.102/.103)"
  if [[ "${edge1_lan}" != "${MINIO_EDGE_1_CANONICAL}" || "${edge2_lan}" != "${MINIO_EDGE_2_CANONICAL}" ]]; then
    fail "minio-edge mgmt IPs do not match canonical contract (.102/.103); refusing to simulate"
    md ""
    md "Result: FAIL (host_vars mismatch vs canonical mgmt IPs)"
    md "Report: ${REPORT_FILE}"
    exit 1
  fi
  ok "edge mgmt IPs match canonical contract"

  if [[ "${EDGE}" == "minio-edge-1" ]]; then
    victim="${edge1_lan}"
    survivor="${edge2_lan}"
  else
    victim="${edge2_lan}"
    survivor="${edge1_lan}"
  fi

  pre "Pre-flight: SSH reachability + sudo non-interactive"
  for host in "${edge1_lan}" "${edge2_lan}"; do
    ssh_run "${host}" "sudo -n true" >/dev/null 2>&1 || { fail "cannot sudo -n on ${host} (required)"; exit 1; }
  done
  ok "edges reachable and sudo -n OK"

  pre "Baseline: VIP reachable over strict TLS"
  if ! curl_https_ok "https://${MINIO_VIP}:${MINIO_S3_PORT}/minio/health/live"; then
    fail "VIP not reachable over strict TLS: https://${MINIO_VIP}:${MINIO_S3_PORT}/minio/health/live"
    md ""
    md "Result: FAIL (VIP TLS baseline failed)"
    md "Report: ${REPORT_FILE}"
    exit 1
  fi
  ok "VIP reachable over strict TLS (baseline)"

  pre "Baseline: keepalived + haproxy active on both edges"
  for host in "${edge1_lan}" "${edge2_lan}"; do
    systemd_active "${host}" keepalived || { fail "keepalived not active on ${host}"; exit 1; }
    systemd_active "${host}" haproxy || { fail "haproxy not active on ${host}"; exit 1; }
  done
  ok "keepalived + haproxy active on both edges (baseline)"

  pre "Baseline: exactly one VIP owner"
  holders="$(vip_holders_count "${edge1_lan}" "${edge2_lan}")"
  owner="$(vip_owner "${edge1_lan}" "${edge2_lan}" || true)"
  md ""
  md "## Baseline"
  md ""
  md "- VIP holders count: \`${holders}\`"
  md "- VIP owner: \`${owner:-none}\`"
  if [[ "${holders}" -ne 1 || -z "${owner}" ]]; then
    fail "expected exactly one VIP owner; got holders=${holders} owner=${owner:-none}"
    md ""
    md "Result: FAIL (VIP ownership baseline failed; split-brain risk)"
    md "Report: ${REPORT_FILE}"
    exit 1
  fi
  ok "VIP ownership baseline OK (owner=${owner})"

  if [[ "${owner}" == "${victim}" ]]; then
    inj "Selected EDGE is current VIP owner; failover should move VIP to survivor (${survivor})"
  else
    inj "Selected EDGE is standby; stopping it should not impact VIP reachability"
  fi

  stopped=0
  cleanup() {
    if [[ "${stopped}" -eq 1 ]]; then
      rec "Attempting to restore keepalived + haproxy on victim ${victim}"
      ssh_run "${victim}" "sudo -n systemctl start keepalived haproxy" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup EXIT

  inj "Inject failure on ${EDGE} (${victim}): stop haproxy then keepalived"
  ssh_run "${victim}" "sudo -n systemctl stop haproxy" >/dev/null
  ssh_run "${victim}" "sudo -n systemctl stop keepalived" >/dev/null
  stopped=1
  ok "services stopped on victim edge"

  inj "Wait for VIP failover (if needed)"
  if [[ "${owner}" == "${victim}" ]]; then
    if ! wait_vip_owner "${survivor}" "${edge1_lan}" "${edge2_lan}" 60 >/dev/null; then
      fail "VIP did not move to survivor within timeout"
      exit 1
    fi
    ok "VIP moved to survivor"
  else
    ok "victim was standby; no VIP move required"
  fi

  inj "Confirm victim does not own VIP"
  if ssh_run "${victim}" "ip -4 addr show | grep -q \"${MINIO_VIP}/\""; then
    fail "victim still owns VIP after keepalived stop (unexpected)"
    exit 1
  fi
  ok "victim does not own VIP"

  check "Post-failure: VIP still reachable over strict TLS"
  if ! curl_https_ok "https://${MINIO_VIP}:${MINIO_S3_PORT}/minio/health/live"; then
    fail "VIP not reachable after edge failure (strict TLS)"
    exit 1
  fi
  ok "VIP reachable after edge failure (strict TLS)"

  check "Post-failure: survivor services active"
  systemd_active "${survivor}" keepalived || { fail "keepalived not active on survivor ${survivor}"; exit 1; }
  systemd_active "${survivor}" haproxy || { fail "haproxy not active on survivor ${survivor}"; exit 1; }
  ok "survivor keepalived + haproxy active"

  check "Post-failure: victim services stopped"
  if ssh_run "${victim}" "sudo -n systemctl is-active --quiet keepalived"; then
    fail "keepalived unexpectedly active on victim"
    exit 1
  fi
  if ssh_run "${victim}" "sudo -n systemctl is-active --quiet haproxy"; then
    fail "haproxy unexpectedly active on victim"
    exit 1
  fi
  ok "victim keepalived + haproxy stopped"

  rec "Recovery: start keepalived + haproxy on victim"
  ssh_run "${victim}" "sudo -n systemctl start keepalived haproxy" >/dev/null
  stopped=0

  rec "Wait for victim to be healthy"
  for _ in $(seq 1 30); do
    if systemd_active "${victim}" keepalived && systemd_active "${victim}" haproxy; then
      ok "victim services active again"
      break
    fi
    sleep 1
  done
  systemd_active "${victim}" keepalived || { fail "keepalived not active on victim after recovery"; exit 1; }
  systemd_active "${victim}" haproxy || { fail "haproxy not active on victim after recovery"; exit 1; }

  rec "Final: ensure no split-brain (exactly one VIP owner)"
  holders2="$(vip_holders_count "${edge1_lan}" "${edge2_lan}")"
  owner2="$(vip_owner "${edge1_lan}" "${edge2_lan}" || true)"
  md ""
  md "## Post-recovery"
  md ""
  md "- VIP holders count: \`${holders2}\`"
  md "- VIP owner: \`${owner2:-none}\`"
  if [[ "${holders2}" -ne 1 || -z "${owner2}" ]]; then
    fail "VIP ownership invalid after recovery (holders=${holders2} owner=${owner2:-none})"
    exit 1
  fi
  ok "VIP ownership steady after recovery (owner=${owner2})"

  rec "Final: VIP reachable over strict TLS"
  if ! curl_https_ok "https://${MINIO_VIP}:${MINIO_S3_PORT}/minio/health/live"; then
    fail "VIP not reachable after recovery"
    exit 1
  fi
  ok "VIP reachable after recovery"

  md ""
  md "## Result"
  md ""
  md "- Result: PASS"

  log ""
  log "=== MinIO edge failure simulation: PASS ==="
  log "Report: ${REPORT_FILE}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
