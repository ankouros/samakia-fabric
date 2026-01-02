#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export FABRIC_REPO_ROOT="${ROOT_DIR}"

expect_ci_block() {
  local label="$1"
  shift
  local output
  set +e
  output="$("$@" 2>&1)"
  local rc=$?
  set -e
  if [[ ${rc} -eq 0 ]]; then
    echo "ERROR: ${label} unexpectedly succeeded in CI" >&2
    exit 1
  fi
  if ! grep -q "not allowed in CI" <<<"${output}"; then
    echo "ERROR: ${label} did not report CI guard" >&2
    echo "Output was:" >&2
    echo "${output}" >&2
    exit 1
  fi
  echo "PASS: ${label} blocked in CI"
}

expect_ci_block "bindings.apply execute" bash -c "CI=1 BIND_EXECUTE=1 TENANT=project-birds WORKLOAD=birds-api make -C \"${ROOT_DIR}\" bindings.apply"

expect_ci_block "bindings.verify.live" bash -c "CI=1 VERIFY_LIVE=1 TENANT=project-birds make -C \"${ROOT_DIR}\" bindings.verify.live"

expect_ci_block "bindings.secrets.materialize execute" bash -c "CI=1 MATERIALIZE_EXECUTE=1 TENANT=all bash \"${ROOT_DIR}/ops/bindings/secrets/materialize.sh\""

expect_ci_block "bindings.secrets.rotate execute" bash -c "CI=1 ROTATE_EXECUTE=1 TENANT=all bash \"${ROOT_DIR}/ops/bindings/rotate/rotate.sh\""

expect_ci_block "proposals.approve" bash -c "CI=1 OPERATOR_APPROVE=1 APPROVER_ID=test PROPOSAL_ID=example bash \"${ROOT_DIR}/ops/proposals/approve.sh\""

expect_ci_block "proposals.reject" bash -c "CI=1 OPERATOR_REJECT=1 APPROVER_ID=test PROPOSAL_ID=example bash \"${ROOT_DIR}/ops/proposals/reject.sh\""

expect_ci_block "proposals.apply execute" bash -c "CI=1 PROPOSAL_APPLY=1 PROPOSAL_ID=example bash \"${ROOT_DIR}/ops/proposals/apply.sh\""
