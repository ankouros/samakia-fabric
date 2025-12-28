#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  ha-precheck.sh [--ctids <id...>] [--shared-storages "s1,s2"] [--local-storages "l1,l2"]

Read-only precheck for Proxmox HA GameDays.

What it checks (best-effort, read-only):
  - cluster quorum (pvecm status)
  - HA services active (pve-ha-crm, pve-ha-lrm)
  - HA manager reachable (pve-ha-manager status)
  - optional: target CTs exist and are HA-managed (ha-manager/pve-ha-manager output)
  - optional: reports rootfs storage name for each CTID

Hard rules:
  - No writes.
  - No network calls.
  - No automated shutdowns or tampering.

Notes:
  - Storage "shared vs local" cannot be reliably inferred without operator input.
    Use --shared-storages / --local-storages lists to get a stronger PASS/FAIL gate.
EOF
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

ctids=()
shared_storages=""
local_storages=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ctids)
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
        ctids+=("$1")
        shift
      done
      ;;
    --shared-storages)
      shared_storages="${2:-}"
      shift 2
      ;;
    --local-storages)
      local_storages="${2:-}"
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

require_cmd awk
require_cmd sed
require_cmd grep
require_cmd systemctl

pass=1

section() { printf '\n== %s ==\n' "$1"; }
ok() { printf 'OK: %s\n' "$1"; }
warn() { printf 'WARN: %s\n' "$1" >&2; }
fail() { printf 'FAIL: %s\n' "$1" >&2; pass=0; }

section "Cluster quorum"
if command -v pvecm >/dev/null 2>&1; then
  out="$(pvecm status 2>/dev/null || true)"
  if echo "${out}" | grep -Eq '^Quorate:\s+Yes\b'; then
    ok "Cluster quorate"
  else
    fail "Cluster not quorate (or unable to determine); run: pvecm status"
  fi
else
  warn "pvecm not found; cannot check quorum on this host"
fi

section "HA services"
crm="$(systemctl is-active pve-ha-crm 2>/dev/null || true)"
lrm="$(systemctl is-active pve-ha-lrm 2>/dev/null || true)"
if [[ "${crm}" == "active" ]]; then
  ok "pve-ha-crm is active"
else
  fail "pve-ha-crm is not active (${crm})"
fi
if [[ "${lrm}" == "active" ]]; then
  ok "pve-ha-lrm is active"
else
  fail "pve-ha-lrm is not active (${lrm})"
fi

section "HA manager status"
if command -v pve-ha-manager >/dev/null 2>&1; then
  if pve-ha-manager status >/dev/null 2>&1; then
    ok "pve-ha-manager status reachable"
  else
    fail "pve-ha-manager status failed"
  fi
elif command -v ha-manager >/dev/null 2>&1; then
  if ha-manager status >/dev/null 2>&1; then
    ok "ha-manager status reachable"
  else
    fail "ha-manager status failed"
  fi
else
  warn "No HA manager CLI found (pve-ha-manager/ha-manager); cannot check HA resources"
fi

ha_status_text=""
if command -v pve-ha-manager >/dev/null 2>&1; then
  ha_status_text="$(pve-ha-manager status 2>/dev/null || true)"
elif command -v ha-manager >/dev/null 2>&1; then
  ha_status_text="$(ha-manager status 2>/dev/null || true)"
fi

if [[ ${#ctids[@]} -gt 0 ]]; then
  section "Target CTs"
  if ! command -v pct >/dev/null 2>&1; then
    fail "pct not found; cannot inspect CT configs"
  else
    for id in "${ctids[@]}"; do
      if ! pct config "${id}" >/dev/null 2>&1; then
        fail "CTID ${id}: pct config failed (does CT exist on this cluster?)"
        continue
      fi

      rootfs_line="$(pct config "${id}" 2>/dev/null | awk -F': ' '$1=="rootfs"{print $2; exit}')"
      storage="unknown"
      if [[ -n "${rootfs_line}" ]]; then
        storage="$(printf '%s' "${rootfs_line}" | awk -F: '{print $1}')"
      fi
      ok "CTID ${id}: rootfs storage=${storage}"

      if [[ -n "${ha_status_text}" ]]; then
        if echo "${ha_status_text}" | grep -Eq "lxc:${id}\\b"; then
          ok "CTID ${id}: HA resource present (lxc:${id})"
        else
          fail "CTID ${id}: not HA-managed (missing lxc:${id} in HA status); do not use as GameDay target"
        fi
      else
        warn "CTID ${id}: HA resource presence not checked (no HA status output available)"
      fi

      if [[ -n "${shared_storages}" || -n "${local_storages}" ]]; then
        IFS=',' read -r -a shared_arr <<<"${shared_storages}"
        IFS=',' read -r -a local_arr <<<"${local_storages}"
        is_shared=0
        is_local=0
        for s in "${shared_arr[@]}"; do
          [[ "${s}" == "${storage}" ]] && is_shared=1
        done
        for s in "${local_arr[@]}"; do
          [[ "${s}" == "${storage}" ]] && is_local=1
        done

        if [[ "${is_local}" -eq 1 ]]; then
          fail "CTID ${id}: uses local storage (${storage}); not migratable for HA simulations that require migration"
        elif [[ "${is_shared}" -eq 1 ]]; then
          ok "CTID ${id}: uses declared shared storage (${storage})"
        else
          warn "CTID ${id}: storage (${storage}) not classified by operator lists; validate migratability manually"
        fi
      fi
    done
  fi
fi

if [[ "${pass}" -eq 1 ]]; then
  echo
  echo "PASS: HA GameDay prechecks OK"
  exit 0
fi

echo
echo "FAIL: HA GameDay prechecks failed (see messages above)" >&2
exit 1
