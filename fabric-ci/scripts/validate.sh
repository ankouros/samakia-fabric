#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

export ANSIBLE_CONFIG="$REPO_ROOT/fabric-core/ansible/ansible.cfg"


ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TERRAFORM_ENVS_DIR="$ROOT_DIR/fabric-core/terraform/envs"
ANSIBLE_DIR="$ROOT_DIR/fabric-core/ansible"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd terraform
require_cmd ansible-playbook
require_cmd ansible-inventory

export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"

# Golden image versioning unit test (no packer, no Proxmox).
bash "$ROOT_DIR/ops/scripts/test-image-next-version.sh"

# MinIO quorum guard decision logic unit test (offline; no Proxmox/MinIO).
bash "$ROOT_DIR/ops/scripts/test-minio-quorum-guard.sh"

# MinIO Terraform backend smoke parsing unit test (offline; no MinIO/Proxmox).
bash "$ROOT_DIR/ops/scripts/test-minio-terraform-backend-smoke.sh"

bash "$ROOT_DIR/fabric-ci/scripts/check-proxmox-ca-and-tls.sh"

for env_dir in "$TERRAFORM_ENVS_DIR"/*; do
  if [[ -d "$env_dir" ]] && compgen -G "$env_dir/*.tf" >/dev/null; then
    terraform -chdir="$env_dir" init -backend=false
    terraform -chdir="$env_dir" validate
  fi
done

# Inventory resolution is environment-dependent; validate it only when Proxmox
# credentials are present (token or user/pass).
if [[ -n "${TF_VAR_pm_api_url:-}" && -n "${TF_VAR_pm_api_token_id:-}" && -n "${TF_VAR_pm_api_token_secret:-}" ]]; then
  ansible-inventory --list >/dev/null
fi

# Syntax checks must not depend on runtime inventory connectivity.
ansible-playbook -i localhost, "$ANSIBLE_DIR/playbooks/bootstrap.yml" --syntax-check
ansible-playbook -i localhost, "$ANSIBLE_DIR/playbooks/harden.yml" --syntax-check
ansible-playbook -i localhost, "$ANSIBLE_DIR/playbooks/hardening.yml" --syntax-check
ansible-playbook -i localhost, "$ANSIBLE_DIR/playbooks/k8s-prereqs.yml" --syntax-check
ansible-playbook -i localhost, "$ANSIBLE_DIR/playbooks/dns.yml" --syntax-check
ansible-playbook -i localhost, "$ANSIBLE_DIR/playbooks/dns-edge.yml" --syntax-check
ansible-playbook -i localhost, "$ANSIBLE_DIR/playbooks/dns-auth.yml" --syntax-check
ansible-playbook -i localhost, "$ANSIBLE_DIR/playbooks/minio.yml" --syntax-check
ansible-playbook -i localhost, "$ANSIBLE_DIR/playbooks/minio-edge.yml" --syntax-check
ansible-playbook -i localhost, "$ANSIBLE_DIR/playbooks/state-backend.yml" --syntax-check

echo "Validation checks completed"
