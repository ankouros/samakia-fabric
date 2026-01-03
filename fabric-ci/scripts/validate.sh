#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

export ANSIBLE_CONFIG="$REPO_ROOT/fabric-core/ansible/ansible.cfg"


ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TERRAFORM_ENVS_DIR="$ROOT_DIR/fabric-core/terraform/envs"
ANSIBLE_DIR="$ROOT_DIR/fabric-core/ansible"
export FABRIC_REPO_ROOT="$ROOT_DIR"
export TF_VAR_fabric_repo_root="$ROOT_DIR"

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

# Shared observability ingestion acceptance parsing (offline).
bash "$ROOT_DIR/ops/scripts/test-shared-obs-ingest-accept.sh"

# Shared runtime invariants evaluation (offline).
bash "$ROOT_DIR/ops/scripts/test-shared-runtime-invariants-accept.sh"

# Compliance evaluation (offline; no secrets).
bash "$ROOT_DIR/ops/scripts/test-compliance-eval.sh"

# DNS rrset check unit test (offline; no Proxmox/DNS needed).
bash "$ROOT_DIR/ops/scripts/test-dns-rrset-check.sh"

# HA enforcement override test (offline; no Proxmox needed).
bash "$ROOT_DIR/ops/scripts/ha/test-enforce-placement.sh"

# Phase 12 closure regression checks (offline).
bash "$ROOT_DIR/ops/scripts/test-phase12/test-phase12-targets.sh"
bash "$ROOT_DIR/ops/scripts/test-phase12/test-phase12-guards.sh"
bash "$ROOT_DIR/ops/scripts/test-phase12/test-phase12-docs-generated.sh"
bash "$ROOT_DIR/ops/scripts/test-phase12/test-phase12-readiness-packet.sh"
bash "$ROOT_DIR/ops/scripts/test-milestone/test-wrapper-exit-semantics.sh"

# AI regression guardrails (offline).
bash "$ROOT_DIR/ops/scripts/test-ai/test-no-exec.sh"
bash "$ROOT_DIR/ops/scripts/test-ai/test-no-external-provider.sh"
bash "$ROOT_DIR/ops/scripts/test-ai/test-routing-locked.sh"
bash "$ROOT_DIR/ops/scripts/test-ai/test-mcp-readonly.sh"
bash "$ROOT_DIR/ops/scripts/test-ai/test-ci-safety.sh"
bash "$ROOT_DIR/ops/scripts/test-ai/test-ai-ux.sh"
bash "$ROOT_DIR/ops/scripts/test-ai/test-ai-evidence.sh"
bash "$ROOT_DIR/ops/scripts/test-ai/test-ai-no-new-capabilities.sh"

bash "$ROOT_DIR/fabric-ci/scripts/check-proxmox-ca-and-tls.sh"

for env_dir in "$TERRAFORM_ENVS_DIR"/*; do
  if [[ -d "$env_dir" ]] && compgen -G "$env_dir/*.tf" >/dev/null; then
    # Validate must not require backend credentials and must not depend on any
    # pre-existing `.terraform/` directory (which may be configured for remote state).
    tf_data_dir="$(mktemp -d)"
    TF_DATA_DIR="${tf_data_dir}" terraform -chdir="$env_dir" init -backend=false -input=false
    TF_DATA_DIR="${tf_data_dir}" terraform -chdir="$env_dir" validate
    rm -rf "${tf_data_dir}" 2>/dev/null || true
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
ansible-playbook -i localhost, "$ANSIBLE_DIR/playbooks/ssh-keys-rotate.yml" --syntax-check

echo "Validation checks completed"
