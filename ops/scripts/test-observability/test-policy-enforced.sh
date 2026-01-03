#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

validate_dir="${FABRIC_REPO_ROOT}/ops/observability/validate"
fixtures_dir="${FABRIC_REPO_ROOT}/ops/observability/fixtures"

tmp="$(mktemp)"
trap 'rm -f "${tmp}" 2>/dev/null || true' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

bash "${validate_dir}/validate-policy.sh"

# Good fixture should pass.
bash "${validate_dir}/validate-topology.sh" --tf-output "${fixtures_dir}/terraform-output-good.json" --output "${tmp}"
bash "${validate_dir}/validate-replicas.sh" --topology "${tmp}"
bash "${validate_dir}/validate-affinity.sh" --topology "${tmp}"

# Replica violation should fail.
bash "${validate_dir}/validate-topology.sh" --tf-output "${fixtures_dir}/terraform-output-bad-replicas.json" --output "${tmp}"
if bash "${validate_dir}/validate-replicas.sh" --topology "${tmp}" >/dev/null 2>&1; then
  fail "replica violation did not fail"
fi

# Anti-affinity violation should fail.
bash "${validate_dir}/validate-topology.sh" --tf-output "${fixtures_dir}/terraform-output-bad-affinity.json" --output "${tmp}"
if bash "${validate_dir}/validate-affinity.sh" --topology "${tmp}" >/dev/null 2>&1; then
  fail "anti-affinity violation did not fail"
fi

echo "PASS: shared observability policy enforcement validated"
