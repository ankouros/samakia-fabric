#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FABRIC_REPO_ROOT="$(cd "${script_dir}/../.." && pwd)"
export FABRIC_REPO_ROOT

# shellcheck disable=SC1090
source "${FABRIC_REPO_ROOT}/ops/scripts/minio-terraform-backend-smoke.sh"

t_pass() { echo "PASS: $*"; }
t_fail() { echo "FAIL: $*" >&2; exit 1; }

tmp="$(mktemp -d)"
cleanup() { rm -rf "${tmp}" 2>/dev/null || true; }
trap cleanup EXIT

mkdir -p "${tmp}/.terraform"
cat >"${tmp}/.terraform/terraform.tfstate" <<'JSON'
{
  "backend": {
    "type": "s3",
    "config": {
      "bucket": "samakia-terraform",
      "key": "samakia-fabric/_smoke/minio-backend-smoke/terraform.tfstate",
      "region": "us-east-1",
      "endpoint": "https://192.168.11.101:9000",
      "use_lockfile": true
    }
  }
}
JSON

out="$(smoke_parse_backend_state "${tmp}/.terraform/terraform.tfstate")"
echo "${out}" | rg -q '^type=s3$' || t_fail "expected type=s3"
echo "${out}" | rg -q '^endpoint=https://192\.168\.11\.101:9000$' || t_fail "expected endpoint"
echo "${out}" | rg -q '^use_lockfile=True|^use_lockfile=true$' || t_fail "expected use_lockfile=true"
t_pass "backend metadata parser extracts s3/endpoint/use_lockfile"

sample_init='Initializing the backend...
Successfully configured the backend "s3"!'
smoke_init_output_has_s3_backend "${sample_init}" || t_fail "expected init output to be recognized as s3"
t_pass "init output parser recognizes s3 backend marker"
