#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: required file missing: ${path}" >&2
    exit 1
  fi
}

require_exec() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: required executable missing: ${path}" >&2
    exit 1
  fi
}

schema="${FABRIC_REPO_ROOT}/contracts/proposals/proposal.schema.json"
examples_dir="${FABRIC_REPO_ROOT}/examples/proposals"

require_file "${schema}"
if [[ ! -d "${examples_dir}" ]]; then
  echo "ERROR: proposal examples directory missing: ${examples_dir}" >&2
  exit 1
fi

scripts=(
  "submit.sh"
  "validate.sh"
  "diff.sh"
  "impact.sh"
  "review.sh"
  "approve.sh"
  "reject.sh"
  "decision.sh"
  "apply.sh"
  "redact.sh"
)

for script in "${scripts[@]}"; do
  require_exec "${FABRIC_REPO_ROOT}/ops/proposals/${script}"
done

if ! rg -n "PROPOSAL_APPLY=1" "${FABRIC_REPO_ROOT}/ops/proposals/apply.sh" >/dev/null 2>&1; then
  echo "ERROR: proposal apply guard missing (PROPOSAL_APPLY=1)" >&2
  exit 1
fi

if ! rg -n "decision.sha256.asc" "${FABRIC_REPO_ROOT}/ops/proposals/apply.sh" >/dev/null 2>&1; then
  echo "ERROR: prod decision signature verification missing in apply path" >&2
  exit 1
fi

if ! rg -n "OPERATOR_APPROVE=1" "${FABRIC_REPO_ROOT}/ops/proposals/approve.sh" >/dev/null 2>&1; then
  echo "ERROR: proposal approve guard missing (OPERATOR_APPROVE=1)" >&2
  exit 1
fi

if ! rg -n "OPERATOR_REJECT=1" "${FABRIC_REPO_ROOT}/ops/proposals/reject.sh" >/dev/null 2>&1; then
  echo "ERROR: proposal reject guard missing (OPERATOR_REJECT=1)" >&2
  exit 1
fi

if ! rg -n "prod approval requires EVIDENCE_SIGN=1" "${FABRIC_REPO_ROOT}/ops/proposals/decision.sh" >/dev/null 2>&1; then
  echo "ERROR: prod signing requirement missing in decision gate" >&2
  exit 1
fi

if ! PROPOSAL_ID=example bash "${FABRIC_REPO_ROOT}/ops/proposals/validate.sh" >/dev/null 2>&1; then
  echo "ERROR: proposal examples failed validation" >&2
  exit 1
fi

echo "policy-proposals: OK"
