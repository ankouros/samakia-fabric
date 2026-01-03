#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export FABRIC_REPO_ROOT="${ROOT_DIR}"

out_dir="${ROOT_DIR}/evidence/compliance-test"

bash "${ROOT_DIR}/ops/scripts/compliance-eval.sh" --profile baseline --output "${out_dir}/baseline"
bash "${ROOT_DIR}/ops/scripts/compliance-eval.sh" --profile hardened --output "${out_dir}/hardened"
