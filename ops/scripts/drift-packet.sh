#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  drift-packet.sh <env> [--sample] [--out-dir <path>]

Creates a read-only drift evidence packet under:
  evidence/drift/<env>/<UTC>/

Options:
  --sample        Offline sample packet (no Terraform/Ansible, no network)
  --out-dir PATH  Override output directory (default: evidence/drift/<env>/<UTC>)

Notes:
  - No terraform apply; plan only.
  - Secrets are never printed; outputs are redacted.
EOT
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
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

redact_stream() {
  sed -E \
    -e 's/(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN)=([^[:space:]]+)/\1=<redacted>/g' \
    -e 's/(TF_VAR_pm_api_token_secret|PM_API_TOKEN_SECRET)=([^[:space:]]+)/\1=<redacted>/g' \
    -e 's/(TF_VAR_pm_api_token_id|PM_API_TOKEN_ID)=([^[:space:]]+)/\1=<redacted>/g'
}

ENV_NAME="${1:-${ENV:-}}"
shift $(( $# >= 1 ? 1 : $# ))

sample=0
out_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sample)
      sample=1
      shift
      ;;
    --out-dir)
      out_dir="${2:-}"
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

if [[ -z "${ENV_NAME}" ]]; then
  usage
  exit 2
fi

require_cmd date
require_cmd git
require_cmd python3
require_cmd sha256sum
require_cmd find
require_cmd sort
require_cmd xargs
require_cmd sed
require_cmd awk

if [[ "${sample}" -ne 1 ]]; then
  require_cmd terraform
  require_cmd ansible-playbook
fi

env_file="${RUNNER_ENV_FILE:-${HOME}/.config/samakia-fabric/env.sh}"
if [[ -f "${env_file}" ]]; then
  # shellcheck disable=SC1090
  source "${env_file}"
fi

stamp="${AUDIT_TIMESTAMP_UTC:-$(date -u +%Y%m%dT%H%M%SZ)}"
commit_full="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
commit_short="$(git -C "${FABRIC_REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

if [[ -z "${out_dir}" ]]; then
  out_dir="${FABRIC_REPO_ROOT}/evidence/drift/${ENV_NAME}/${stamp}"
fi
mkdir -p "${out_dir}"

plan_txt="${out_dir}/terraform-plan.txt"
ansible_txt="${out_dir}/ansible-check.txt"
meta_json="${out_dir}/metadata.json"
manifest="${out_dir}/manifest.sha256"

backend_mode="remote"
tf_plan_rc=0
ansible_rc=0

if [[ "${sample}" -eq 1 ]]; then
  backend_mode="sample"
  cat >"${plan_txt}" <<'PLAN'
No changes. Infrastructure matches the configuration.
PLAN
  cat >"${ansible_txt}" <<'ANSIBLE'
PLAY RECAP *************************************************************
example : ok=1 changed=0 unreachable=0 failed=0
ANSIBLE
else
  env_dir="${FABRIC_REPO_ROOT}/fabric-core/terraform/envs/${ENV_NAME}"
  if [[ ! -d "${env_dir}" ]]; then
    echo "ERROR: Terraform env directory not found: ${env_dir}" >&2
    exit 1
  fi

  if [[ "${ENV_NAME}" == "samakia-minio" ]]; then
    backend_mode="local"
    work_dir="$(mktemp -d)"
    # shellcheck disable=SC2317 # invoked via trap
    cleanup() { rm -rf "${work_dir}" 2>/dev/null || true; }
    trap cleanup EXIT
    rm -rf "${work_dir}/.terraform" || true
    rm -f "${work_dir}"/*.tf "${work_dir}/.terraform.lock.hcl" 2>/dev/null || true
    for f in "${env_dir}"/*.tf "${env_dir}"/.terraform.lock.hcl; do
      base="$(basename "${f}")"
      if [[ "${base}" == "backend.tf" ]]; then
        continue
      fi
      cp -f "${f}" "${work_dir}/"
    done
    if [[ -s "${env_dir}/terraform.tfstate" ]]; then
      cp -f "${env_dir}/terraform.tfstate" "${work_dir}/terraform.tfstate"
    fi
    if [[ -s "${env_dir}/terraform.tfstate.backup" ]]; then
      cp -f "${env_dir}/terraform.tfstate.backup" "${work_dir}/terraform.tfstate.backup"
    fi

    terraform -chdir="${work_dir}" init -input=false -backend=false -reconfigure >/dev/null
    terraform -chdir="${work_dir}" validate

    tf_plan_raw="${work_dir}/plan.raw"
    set +e
    terraform -chdir="${work_dir}" plan -input=false -lock=false -detailed-exitcode -no-color >"${tf_plan_raw}" 2>&1
    tf_plan_rc=$?
    set -e
    redact_stream <"${tf_plan_raw}" >"${plan_txt}"
  else
    require_env TF_BACKEND_S3_ENDPOINT
    require_env TF_BACKEND_S3_BUCKET
    require_env TF_BACKEND_S3_REGION
    require_env AWS_ACCESS_KEY_ID
    require_env AWS_SECRET_ACCESS_KEY
    require_env TF_VAR_pm_api_url
    require_env TF_VAR_pm_api_token_id
    require_env TF_VAR_pm_api_token_secret

    bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/check-proxmox-ca-and-tls.sh"

    key_prefix="${TF_BACKEND_S3_KEY_PREFIX:-samakia-fabric}"
    key="${key_prefix}/${ENV_NAME}/terraform.tfstate"
    backend_cfg="$(mktemp)"
    tf_data_dir="$(mktemp -d)"
    # shellcheck disable=SC2317 # invoked via trap
    cleanup() { rm -rf "${backend_cfg}" "${tf_data_dir}" 2>/dev/null || true; }
    trap cleanup EXIT

    cat >"${backend_cfg}" <<BACKEND_CFG
bucket         = "${TF_BACKEND_S3_BUCKET}"
key            = "${key}"
region         = "${TF_BACKEND_S3_REGION}"
endpoint       = "${TF_BACKEND_S3_ENDPOINT}"
force_path_style = true
skip_region_validation      = true
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_requesting_account_id  = true
use_lockfile = true
BACKEND_CFG

    TF_DATA_DIR="${tf_data_dir}" terraform -chdir="${env_dir}" init -input=false -lockfile=readonly -backend-config="${backend_cfg}" -reconfigure >/dev/null
    TF_DATA_DIR="${tf_data_dir}" terraform -chdir="${env_dir}" validate

    tf_plan_raw="${out_dir}/plan.raw"
    set +e
    TF_DATA_DIR="${tf_data_dir}" terraform -chdir="${env_dir}" plan -input=false -lock-timeout="${TF_LOCK_TIMEOUT:-60s}" -detailed-exitcode -no-color >"${tf_plan_raw}" 2>&1
    tf_plan_rc=$?
    set -e
    redact_stream <"${tf_plan_raw}" >"${plan_txt}"
    rm -f "${tf_plan_raw}" 2>/dev/null || true
  fi

  if [[ "${SKIP_ANSIBLE:-0}" -eq 1 ]]; then
    echo "Ansible check skipped (SKIP_ANSIBLE=1)" >"${ansible_txt}"
    ansible_rc=0
  else
    ANSIBLE_DIR="${FABRIC_REPO_ROOT}/fabric-core/ansible"
    export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"
    export FABRIC_TERRAFORM_ENV="${ENV_NAME}"
    ansible_raw="${out_dir}/ansible.raw"
    set +e
    ansible-playbook -i "${ANSIBLE_DIR}/inventory/terraform.py" "${ANSIBLE_DIR}/playbooks/harden.yml" --check --diff >"${ansible_raw}" 2>&1
    ansible_rc=$?
    set -e
    redact_stream <"${ansible_raw}" >"${ansible_txt}"
    rm -f "${ansible_raw}" 2>/dev/null || true
  fi
fi

ansible_status="OK"
case "${ansible_rc}" in
  0) ansible_status="OK (no changes)" ;;
  2) ansible_status="DRIFT (would change)" ;;
  4) ansible_status="WARNING (unreachable hosts)" ;;
  *) ansible_status="ERROR (failed)" ;;
esac

terraform_status="OK"
case "${tf_plan_rc}" in
  0) terraform_status="OK (no changes)" ;;
  2) terraform_status="DRIFT (plan has changes)" ;;
  1) terraform_status="ERROR (plan failed)" ;;
  *) terraform_status="ERROR (plan failed)" ;;
esac

python3 - "${meta_json}" "${ENV_NAME}" "${stamp}" "${commit_full}" "${commit_short}" "${backend_mode}" "${terraform_status}" "${ansible_status}" "${tf_plan_rc}" "${ansible_rc}" "${sample}" <<'PY'
import json
import sys

out, env_name, stamp, commit_full, commit_short, backend_mode, tf_status, ans_status, tf_rc, ans_rc, sample = sys.argv[1:12]

doc = {
    "timestamp_utc": stamp,
    "environment": env_name,
    "git_commit": commit_full,
    "git_commit_short": commit_short,
    "backend_mode": backend_mode,
    "sample": sample == "1",
    "terraform": {
        "status": tf_status,
        "exit_code": int(tf_rc),
    },
    "ansible": {
        "status": ans_status,
        "exit_code": int(ans_rc),
    },
}

with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

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

if [[ "${sample}" -eq 1 ]]; then
  echo "OK: wrote sample drift packet: ${out_dir}"
else
  echo "OK: wrote drift packet: ${out_dir}"
fi

if [[ "${tf_plan_rc}" -eq 1 || ( "${ansible_rc}" -ne 0 && "${ansible_rc}" -ne 2 && "${ansible_rc}" -ne 4 ) ]]; then
  exit 1
fi

if [[ "${tf_plan_rc}" -eq 2 || "${ansible_rc}" -eq 2 ]]; then
  exit 2
fi

exit 0
