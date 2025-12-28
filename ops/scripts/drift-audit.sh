#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: missing required env var: ${name}" >&2
    exit 1
  fi
}

ENV_NAME="${1:-}"
if [[ -z "${ENV_NAME}" ]]; then
  echo "Usage: $0 <terraform-env-name>" >&2
  echo "Example: $0 samakia-prod" >&2
  exit 2
fi

TF_ENV_DIR="${REPO_ROOT}/fabric-core/terraform/envs/${ENV_NAME}"
if [[ ! -d "${TF_ENV_DIR}" ]]; then
  echo "ERROR: Terraform env directory not found: ${TF_ENV_DIR}" >&2
  exit 1
fi

require_cmd terraform
require_cmd python3
require_cmd ansible-playbook
require_cmd git
require_cmd grep

require_env TF_VAR_pm_api_url
require_env TF_VAR_pm_api_token_id
require_env TF_VAR_pm_api_token_secret

# Guardrails: strict TLS and internal CA on runner host.
bash "${REPO_ROOT}/fabric-ci/scripts/check-proxmox-ca-and-tls.sh"

if grep -R -n -E '^\s*backend\s+"' "${TF_ENV_DIR}"/*.tf >/dev/null 2>&1; then
  echo "ERROR: remote backend detected in ${TF_ENV_DIR}; drift-audit refuses to run because it must not modify remote state." >&2
  exit 1
fi

timestamp_utc="${AUDIT_TIMESTAMP_UTC:-$(date -u +%Y%m%dT%H%M%SZ)}"
commit_sha="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

if [[ -n "${AUDIT_OUT_DIR:-}" ]]; then
  audit_root="${AUDIT_OUT_DIR}"
else
  audit_root="${REPO_ROOT}/audit/${ENV_NAME}/${timestamp_utc}"
fi
mkdir -p "${audit_root}"

tf_plan_txt="${audit_root}/terraform-plan.txt"
tf_plan_json="${audit_root}/terraform-plan.json"
ansible_txt="${audit_root}/ansible-harden-check.txt"
report_md="${audit_root}/report.md"

main_tf="${TF_ENV_DIR}/main.tf"
template_version="$(
  python3 - "${main_tf}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8") if path.exists() else ""
m = re.search(r'(?m)^\s*lxc_rootfs_version\s*=\s*"([^"]+)"\s*$', text)
print(m.group(1) if m else "unknown")
PY
)"

template_ref="$(
  python3 - "${main_tf}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8") if path.exists() else ""
m = re.search(r'(?m)^\s*lxc_template\s*=\s*"([^"]+)"\s*$', text)
print(m.group(1) if m else "unknown")
PY
)"

tf_workdir="$(mktemp -d)"
# shellcheck disable=SC2317 # invoked via trap
cleanup() { rm -rf "${tf_workdir}"; }
trap cleanup EXIT

shopt -s nullglob
cp "${TF_ENV_DIR}/"*.tf "${tf_workdir}/"
if [[ -f "${TF_ENV_DIR}/.terraform.lock.hcl" ]]; then
  cp "${TF_ENV_DIR}/.terraform.lock.hcl" "${tf_workdir}/"
fi
if compgen -G "${TF_ENV_DIR}/terraform.tfstate*" >/dev/null; then
  cp "${TF_ENV_DIR}/terraform.tfstate"* "${tf_workdir}/"
fi
shopt -u nullglob

tf_init_rc=0
tf_validate_rc=0
tf_plan_rc=0

{
  echo "# Drift Audit Report"
  echo
  echo "- Timestamp (UTC): \`${timestamp_utc}\`"
  echo "- Environment: \`${ENV_NAME}\`"
  echo "- Git commit: \`${commit_sha}\`"
  echo "- Pinned template version: \`${template_version}\`"
  echo "- Pinned template ref: \`${template_ref}\`"
  echo
  echo "## Terraform Drift"
  echo
} >"${report_md}"

set +e
terraform -chdir="${tf_workdir}" init -input=false -lockfile=readonly >/dev/null 2>&1
tf_init_rc=$?
set -e

if [[ "${tf_init_rc}" -ne 0 ]]; then
  {
    echo "- Status: \`ERROR\` (terraform init failed)"
    echo "- Note: This audit refuses to run if it would need to change lockfiles or state in-place."
  } >>"${report_md}"
  exit 1
fi

set +e
terraform -chdir="${tf_workdir}" validate -no-color >/dev/null 2>&1
tf_validate_rc=$?
set -e

if [[ "${tf_validate_rc}" -ne 0 ]]; then
  {
    echo "- Status: \`ERROR\` (terraform validate failed)"
    echo "- Action: fix HCL/variables first; drift cannot be assessed."
  } >>"${report_md}"
  exit 1
fi

set +e
terraform -chdir="${tf_workdir}" plan -detailed-exitcode -no-color -input=false -out="${tf_workdir}/plan.bin" >"${tf_plan_txt}" 2>&1
tf_plan_rc=$?
set -e

if [[ "${tf_plan_rc}" -eq 1 ]]; then
  {
    echo "- Status: \`ERROR\` (terraform plan failed)"
    echo "- Log: \`${tf_plan_txt}\`"
  } >>"${report_md}"
  exit 1
fi

terraform -chdir="${tf_workdir}" show -json "${tf_workdir}/plan.bin" >"${tf_plan_json}"

tf_change_summary="$(
  python3 - "${tf_plan_json}" <<'PY'
import json
import sys

plan = json.load(open(sys.argv[1], "r", encoding="utf-8"))
changes = []
for rc in plan.get("resource_changes", []):
    addr = rc.get("address")
    actions = rc.get("change", {}).get("actions", [])
    if not addr or actions == ["no-op"]:
        continue
    changes.append((addr, ",".join(actions)))

if not changes:
    print("No resource changes detected in plan.")
    sys.exit(0)

print(f"{len(changes)} resource(s) with planned changes:")
for addr, actions in sorted(changes):
    print(f"- {addr}: {actions}")
PY
)"

{
  if [[ "${tf_plan_rc}" -eq 0 ]]; then
    echo "- Status: \`OK\` (no changes)"
  else
    echo "- Status: \`DRIFT\` (plan has changes)"
  fi
  echo "- Plan log: \`${tf_plan_txt}\`"
  echo "- Plan JSON: \`${tf_plan_json}\`"
  echo
  echo "### Summary"
  echo
  echo '```text'
  echo "${tf_change_summary}"
  echo '```'
  echo
  echo "## Ansible Drift (check-only)"
  echo
} >>"${report_md}"

ANSIBLE_DIR="${REPO_ROOT}/fabric-core/ansible"
export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"

# Make inventory environment-scoped (inventory script may use this).
export FABRIC_TERRAFORM_ENV="${ENV_NAME}"

set +e
ansible-playbook -i "${ANSIBLE_DIR}/inventory/terraform.py" "${ANSIBLE_DIR}/playbooks/harden.yml" --check --diff >"${ansible_txt}" 2>&1
ansible_rc=$?
set -e

ansible_status="OK"
case "${ansible_rc}" in
  0) ansible_status="OK (no changes)" ;;
  2) ansible_status="DRIFT (would change)" ;;
  4) ansible_status="WARNING (unreachable hosts)" ;;
  *) ansible_status="ERROR (failed)" ;;
esac

{
  echo "- Status: \`${ansible_status}\`"
  echo "- Log: \`${ansible_txt}\`"
  echo
  echo "## Interpretation"
  echo
  echo "- Terraform drift means declared infrastructure != observed state. Remediate only via Git change + explicit \`terraform apply\` (or rebuild/recreate), never by manual edits."
  echo "- Ansible drift means policy would change on re-run. Remediate by updating Ansible (or rebuilding), then re-run \`harden.yml\` normally (non-check mode) with human approval."
  echo "- This report is read-only. No auto-apply, no self-heal, no mutation is performed by design."
} >>"${report_md}"

overall_rc=0
if [[ "${tf_plan_rc}" -eq 2 || "${ansible_rc}" -eq 2 ]]; then
  overall_rc=2
fi
if [[ "${ansible_rc}" -ne 0 && "${ansible_rc}" -ne 2 && "${ansible_rc}" -ne 4 ]]; then
  overall_rc=1
fi

echo "OK: wrote audit report: ${report_md}"
exit "${overall_rc}"
