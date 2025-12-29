#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

MINIO_ENV_CANONICAL="samakia-minio"
MINIO_ENDPOINT_CANONICAL="https://192.168.11.101:9000"

RUNNER_ENV_FILE_DEFAULT="${HOME}/.config/samakia-fabric/env.sh"

usage() {
  cat >&2 <<EOF
Usage:
  minio-terraform-backend-smoke.sh

Purpose:
  Real terraform init + plan against the MinIO S3 backend (strict TLS, lockfiles),
  in an isolated local workspace, with NO infra mutation (no apply).

Inputs:
  ENV=${MINIO_ENV_CANONICAL} (required)
  Uses runner env from ${RUNNER_ENV_FILE_DEFAULT} if present and/or exported vars.

Output:
  audit/minio-backend-smoke/<UTC>/report.md

Notes:
  - This is a hard gate (PASS/FAIL only; no WARN).
  - Workspace under ./_tmp is created and cleaned up automatically.
EOF
}

log() { printf '%s\n' "$*"; }
check() { printf '[CHECK] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; }
md() { printf '%s\n' "$*" >>"${REPORT_FILE}"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { fail "missing required command: $1"; return 1; }
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || { fail "missing required env var: ${name} (run: make backend.configure)"; return 1; }
}

smoke_parse_backend_state() {
  local path="$1"
  python3 - <<'PY' "$path"
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

backend = data.get("backend") or {}
if not isinstance(backend, dict):
    raise SystemExit("backend_not_dict")

typ = backend.get("type") or ""
cfg = backend.get("config") or {}
if not isinstance(cfg, dict):
    cfg = {}

endpoint = cfg.get("endpoint") or cfg.get("endpoints") or ""
bucket = cfg.get("bucket") or ""
key = cfg.get("key") or ""
use_lockfile = cfg.get("use_lockfile")

def norm(v):
    if isinstance(v, (str, int, float, bool)):
        return v
    return ""

print(f"type={norm(typ)}")
print(f"endpoint={norm(endpoint)}")
print(f"bucket={norm(bucket)}")
print(f"key={norm(key)}")
print(f"use_lockfile={use_lockfile}")
PY
}

smoke_init_output_has_s3_backend() {
  local init_out="$1"
  python3 - <<'PY' "$init_out"
import re
import sys

s = sys.argv[1]
patterns = [
    r'Successfully configured the backend\s+\\"s3\\"',
    r'Successfully configured the backend\s+"s3"',
    r'backend\s+\\"s3\\"',
    r'backend\s+"s3"',
]
if not any(re.search(p, s) for p in patterns):
    print("missing_s3_backend_marker", file=sys.stderr)
    sys.exit(1)
PY
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

  # Best-effort load runner env file (does not print secrets).
  if [[ -f "${RUNNER_ENV_FILE_DEFAULT}" ]]; then
    # shellcheck disable=SC1090
    source "${RUNNER_ENV_FILE_DEFAULT}"
  fi

  require_cmd terraform || exit 1
  require_cmd mktemp || exit 1
  require_cmd rm || exit 1
  require_cmd mkdir || exit 1
  require_cmd date || exit 1
  require_cmd python3 || exit 1
  require_cmd rg || exit 1

  require_env TF_BACKEND_S3_ENDPOINT || exit 1
  require_env TF_BACKEND_S3_BUCKET || exit 1
  require_env TF_BACKEND_S3_REGION || exit 1
  require_env TF_BACKEND_S3_KEY_PREFIX || exit 1
  require_env TF_BACKEND_S3_CA_REQUIRED || exit 1
  require_env TF_BACKEND_S3_CA_SRC || exit 1
  require_env AWS_ACCESS_KEY_ID || exit 1
  require_env AWS_SECRET_ACCESS_KEY || exit 1

  if [[ "${TF_BACKEND_S3_ENDPOINT}" != "${MINIO_ENDPOINT_CANONICAL}" ]]; then
    fail "TF_BACKEND_S3_ENDPOINT must be ${MINIO_ENDPOINT_CANONICAL} (VIP-only contract). Got: ${TF_BACKEND_S3_ENDPOINT}"
    exit 1
  fi

  local ts report_dir tmp_root work_dir
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  report_dir="${FABRIC_REPO_ROOT}/audit/minio-backend-smoke/${ts}"
  mkdir -p "${report_dir}"
  chmod 700 "${report_dir}" 2>/dev/null || true
  REPORT_FILE="${report_dir}/report.md"
  : >"${REPORT_FILE}"

  tmp_root="${FABRIC_REPO_ROOT}/_tmp/minio-backend-smoke"
  mkdir -p "${tmp_root}"
  work_dir="$(mktemp -d "${tmp_root}/${ts}-XXXXXX")"

  cleanup() { rm -rf "${work_dir}" 2>/dev/null || true; }
  trap cleanup EXIT

  md "# MinIO Terraform backend smoke test"
  md ""
  md "- Timestamp (UTC): \`${ts}\`"
  md "- ENV: \`${ENV}\`"
  md "- Endpoint: \`${TF_BACKEND_S3_ENDPOINT}\`"
  md "- Bucket: \`${TF_BACKEND_S3_BUCKET}\`"
  md "- Key prefix: \`${TF_BACKEND_S3_KEY_PREFIX}\`"
  md "- Workspace: \`${work_dir}\` (ephemeral; auto-cleaned)"
  md ""

  check "Runner env / CA trust (presence-only; secrets not printed)"
  if ! bash "${FABRIC_REPO_ROOT}/ops/scripts/runner-env-check.sh" --file "${RUNNER_ENV_FILE_DEFAULT}" >/dev/null; then
    fail "runner env check failed; run: make backend.configure && make runner.env.check"
    md "Result: FAIL (runner env check failed)"
    exit 1
  fi
  ok "runner env check OK"

  check "Write minimal Terraform config (isolated; no resources)"
  cat >"${work_dir}/backend.tf" <<'TF'
terraform {
  backend "s3" {}
}
TF
  cat >"${work_dir}/versions.tf" <<'TF'
terraform {
  required_version = ">= 1.10.0"
}
TF
  cat >"${work_dir}/outputs.tf" <<'TF'
output "backend_smoke" {
  value = "ok"
}
TF
  ok "workspace prepared"

  key="${TF_BACKEND_S3_KEY_PREFIX}/_smoke/minio-backend-smoke/terraform.tfstate"
  cfg_file="$(mktemp)"
  cfg_cleanup() { rm -f "${cfg_file}" 2>/dev/null || true; }
  trap cfg_cleanup RETURN

  cat >"${cfg_file}" <<EOF
bucket         = "${TF_BACKEND_S3_BUCKET}"
key            = "${key}"
region         = "${TF_BACKEND_S3_REGION}"
endpoint       = "${TF_BACKEND_S3_ENDPOINT}"
force_path_style = true

# MinIO/S3 compatibility (not a TLS bypass)
skip_region_validation      = true
skip_credentials_validation = true
skip_metadata_api_check     = true

# Locking without DynamoDB
use_lockfile = true
EOF

  md "## Terraform init"
  md ""
  md "- Backend type: \`s3\`"
  md "- Key: \`${key}\`"
  md "- Locking: \`use_lockfile=true\`"
  md ""

  check "terraform init (REAL backend; strict TLS; no prompts)"
  init_out="$({ terraform -chdir="${work_dir}" init -input=false -reconfigure "-backend-config=${cfg_file}" 2>&1; } || true)"
  printf '%s\n' "${init_out}" >"${report_dir}/terraform-init.txt"
  if ! echo "${init_out}" | rg -q "Terraform has been successfully initialized|Successfully configured the backend"; then
    fail "terraform init failed (see report: ${report_dir}/terraform-init.txt)"
    md "Result: FAIL (terraform init failed)"
    exit 1
  fi
  if ! smoke_init_output_has_s3_backend "${init_out}"; then
    fail "terraform init did not confirm backend=s3 (see report: ${report_dir}/terraform-init.txt)"
    md "Result: FAIL (backend type not confirmed in init output)"
    exit 1
  fi
  ok "terraform init OK (backend=s3)"

  check "Backend config sanity from local init metadata (best-effort)"
  backend_meta="${work_dir}/.terraform/terraform.tfstate"
  if [[ ! -f "${backend_meta}" ]]; then
    fail "expected terraform backend metadata file missing: ${backend_meta}"
    md "Result: FAIL (backend metadata missing)"
    exit 1
  fi
  meta_kv="$(smoke_parse_backend_state "${backend_meta}")"
  printf '%s\n' "${meta_kv}" >"${report_dir}/backend-metadata.txt"
  if ! echo "${meta_kv}" | rg -q "^type=s3$"; then
    fail "backend metadata does not report type=s3 (see report: ${report_dir}/backend-metadata.txt)"
    md "Result: FAIL (backend metadata mismatch)"
    exit 1
  fi
  if ! echo "${meta_kv}" | rg -q "^endpoint=${MINIO_ENDPOINT_CANONICAL//\//\\/}$"; then
    fail "backend metadata endpoint mismatch (expected ${MINIO_ENDPOINT_CANONICAL})"
    md "Result: FAIL (backend endpoint mismatch)"
    exit 1
  fi
  if ! echo "${meta_kv}" | rg -q "^use_lockfile=True|^use_lockfile=true$"; then
    fail "backend metadata does not indicate use_lockfile=true (see report: ${report_dir}/backend-metadata.txt)"
    md "Result: FAIL (locking not indicated)"
    exit 1
  fi
  ok "backend metadata OK (endpoint + use_lockfile)"

  md ""
  md "## Terraform plan"
  md ""

  check "terraform plan (read-only; must be empty; locking must be active)"
  set +e
  plan_out="$({ terraform -chdir="${work_dir}" plan -input=false -lock-timeout="15s" -detailed-exitcode; } 2>&1)"
  plan_rc=$?
  set -e
  printf '%s\n' "${plan_out}" >"${report_dir}/terraform-plan.txt"

  if [[ "${plan_rc}" -eq 1 ]]; then
    fail "terraform plan failed (see report: ${report_dir}/terraform-plan.txt)"
    md "Result: FAIL (terraform plan failed)"
    exit 1
  fi
  if [[ "${plan_rc}" -eq 2 ]]; then
    fail "terraform plan shows changes (unexpected for smoke workspace; see report: ${report_dir}/terraform-plan.txt)"
    md "Result: FAIL (plan is not empty)"
    exit 1
  fi
  if ! echo "${plan_out}" | rg -q "No changes\\.|No changes\\. Your infrastructure matches the configuration\\.|No changes\\. Infrastructure is up-to-date\\."; then
    fail "terraform plan output did not include 'No changes' (see report: ${report_dir}/terraform-plan.txt)"
    md "Result: FAIL (plan output unexpected)"
    exit 1
  fi
  if ! echo "${plan_out}" | rg -q "Acquiring state lock|Releasing state lock"; then
    fail "terraform plan did not show state lock activity (locking may be disabled; see report: ${report_dir}/terraform-plan.txt)"
    md "Result: FAIL (locking not observed)"
    exit 1
  fi
  ok "terraform plan OK (no changes; locking observed)"

  md ""
  md "## Verdict"
  md ""
  md "- Result: PASS"
  md ""
  md "## Remediation (if FAIL)"
  md ""
  md "- Run: \`make backend.configure\` then \`make runner.env.check\`."
  md "- Verify MinIO VIP is reachable over strict TLS: \`curl -fsS https://192.168.11.101:9000/minio/health/live\`."
  md "- Verify bucket exists and credentials are correct (runner-local only; never commit secrets)."

  log ""
  log "=== MinIO backend smoke: PASS ==="
  log "Report: ${REPORT_FILE}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
