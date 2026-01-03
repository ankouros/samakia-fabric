#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


missing=0
for path in \
  "${FABRIC_REPO_ROOT}/ops/tenants/execute/execute-policy.yml" \
  "${FABRIC_REPO_ROOT}/ops/tenants/execute/validate-execute-policy.sh" \
  "${FABRIC_REPO_ROOT}/ops/tenants/execute/plan.sh" \
  "${FABRIC_REPO_ROOT}/ops/tenants/execute/apply.sh" \
  "${FABRIC_REPO_ROOT}/ops/tenants/execute/change-window.sh" \
  "${FABRIC_REPO_ROOT}/ops/tenants/execute/signer.sh"

do
  if [[ ! -e "${path}" ]]; then
    echo "MISSING: ${path}"
    missing=1
  fi
done

if [[ "${missing}" -eq 0 ]]; then
  echo "PASS: tenant execute tooling present"
else
  exit 1
fi
