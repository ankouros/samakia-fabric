#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  ssh-keys-rotate.sh [--dry-run|--execute]

Defaults:
  --dry-run (read-only)

Guards:
  ROTATE_EXECUTE=1   Required for execute mode
  BREAK_GLASS=1      Required to apply break-glass keys
  I_UNDERSTAND=1     Required when BREAK_GLASS=1

Configuration:
  ENV                       Terraform env (default: samakia-prod)
  OPERATOR_KEYS_FILE        Authorized_keys file for operator (default: ~/.config/samakia-fabric/ssh-keys/operator/authorized_keys)
  BREAK_GLASS_KEYS_FILE     Authorized_keys file for break-glass (default: ~/.config/samakia-fabric/ssh-keys/break-glass/authorized_keys)
  ANSIBLE_LIMIT             Optional ansible --limit value

Evidence:
  evidence/security/ssh-rotation/<UTC>/
EOT
}

mode="dry-run"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      mode="dry-run"
      shift
      ;;
    --execute)
      mode="execute"
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

env_name="${ENV:-samakia-prod}"
ansible_dir="${FABRIC_REPO_ROOT}/fabric-core/ansible"
playbook="${ansible_dir}/playbooks/ssh-keys-rotate.yml"
inventory="${ansible_dir}/inventory/terraform.py"

operator_keys_file="${OPERATOR_KEYS_FILE:-${HOME}/.config/samakia-fabric/ssh-keys/operator/authorized_keys}"
break_glass_keys_file="${BREAK_GLASS_KEYS_FILE:-${HOME}/.config/samakia-fabric/ssh-keys/break-glass/authorized_keys}"

if [[ ! -f "${operator_keys_file}" ]]; then
  echo "ERROR: operator keys file not found: ${operator_keys_file}" >&2
  exit 2
fi

if [[ "${mode}" == "execute" && "${ROTATE_EXECUTE:-0}" -ne 1 ]]; then
  echo "ERROR: execute mode requires ROTATE_EXECUTE=1" >&2
  exit 2
fi

use_break_glass=0
if [[ "${BREAK_GLASS:-0}" -eq 1 ]]; then
  if [[ "${I_UNDERSTAND:-0}" -ne 1 ]]; then
    echo "ERROR: BREAK_GLASS=1 requires I_UNDERSTAND=1" >&2
    exit 2
  fi
  if [[ ! -f "${break_glass_keys_file}" ]]; then
    echo "ERROR: break-glass keys file not found: ${break_glass_keys_file}" >&2
    exit 2
  fi
  use_break_glass=1
fi

if [[ ! -f "${playbook}" ]]; then
  echo "ERROR: playbook not found: ${playbook}" >&2
  exit 1
fi

if [[ -f "${HOME}/.config/samakia-fabric/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HOME}/.config/samakia-fabric/env.sh"
fi

if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "ERROR: ssh-keygen not found" >&2
  exit 1
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ERROR: ansible-playbook not found" >&2
  exit 1
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="${FABRIC_REPO_ROOT}/evidence/security/ssh-rotation/${stamp}"
mkdir -p "${out_dir}"

operator_fps="$(awk '/^ssh-/{print $0}' "${operator_keys_file}" | ssh-keygen -lf - | awk '{print $2}')"
if [[ -z "${operator_fps}" ]]; then
  echo "ERROR: no operator keys found in ${operator_keys_file}" >&2
  exit 2
fi

break_glass_fps=""
if [[ "${use_break_glass}" -eq 1 ]]; then
  break_glass_fps="$(awk '/^ssh-/{print $0}' "${break_glass_keys_file}" | ssh-keygen -lf - | awk '{print $2}')"
  if [[ -z "${break_glass_fps}" ]]; then
    echo "ERROR: no break-glass keys found in ${break_glass_keys_file}" >&2
    exit 2
  fi
fi

metadata="${out_dir}/metadata.json"
python3 - "${metadata}" "${env_name}" "${stamp}" "${mode}" "${operator_keys_file}" "${break_glass_keys_file}" "${use_break_glass}" "${operator_fps}" "${break_glass_fps}" <<'PY'
import json
import sys

out, env_name, stamp, mode, op_file, bg_file, use_bg, op_fps, bg_fps = sys.argv[1:10]

doc = {
    "timestamp_utc": stamp,
    "environment": env_name,
    "mode": mode,
    "operator_keys_file": op_file,
    "break_glass_requested": use_bg == "1",
    "break_glass_keys_file": bg_file if use_bg == "1" else None,
    "operator_fingerprints": [fp for fp in op_fps.split() if fp],
    "break_glass_fingerprints": [fp for fp in bg_fps.split() if fp],
}

with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

hosts_list="${out_dir}/hosts.txt"
{
  echo "ENV=${env_name}"
  if [[ -n "${ANSIBLE_LIMIT:-}" ]]; then
    echo "limit=${ANSIBLE_LIMIT}"
  else
    echo "limit=<none>"
  fi
} > "${hosts_list}"

manifest="${out_dir}/manifest.sha256"
(
  cd "${out_dir}"
  find . \
    -type f \
    ! -name 'manifest.sha256' \
    ! -name 'manifest.sha256.asc' \
    ! -name 'manifest.sha256.asc.a' \
    ! -name 'manifest.sha256.asc.b' \
    ! -name 'manifest.sha256.tsr' \
    -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >"${manifest}"
)

if [[ "${EVIDENCE_SIGN:-0}" -eq 1 ]]; then
  if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg not found (required for EVIDENCE_SIGN=1)" >&2
    exit 1
  fi
  gpg_args=(--batch --yes --detach-sign)
  if [[ -n "${EVIDENCE_GPG_KEY:-}" ]]; then
    gpg_args+=(--local-user "${EVIDENCE_GPG_KEY}")
  fi
  gpg "${gpg_args[@]}" --output "${manifest}.asc" "${manifest}"
fi

ansible_args=(
  -i "${inventory}"
  "${playbook}"
  -u samakia
  --extra-vars "operator_keys_file=${operator_keys_file}"
  --extra-vars "break_glass_keys_file=${break_glass_keys_file}"
  --extra-vars "use_break_glass=${use_break_glass}"
)

if [[ -n "${ANSIBLE_LIMIT:-}" ]]; then
  ansible_args+=(--limit "${ANSIBLE_LIMIT}")
fi

if [[ "${mode}" == "dry-run" ]]; then
  ansible_args+=(--check --diff)
fi

ANSIBLE_CONFIG="${ansible_dir}/ansible.cfg" FABRIC_TERRAFORM_ENV="${env_name}" ansible-playbook "${ansible_args[@]}"

echo "OK: SSH key rotation ${mode} completed (evidence: ${out_dir})"
