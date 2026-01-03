#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

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

schema="${FABRIC_REPO_ROOT}/contracts/selfservice/proposal.schema.json"
examples_dir="${FABRIC_REPO_ROOT}/examples/selfservice"

require_file "${schema}"
if [[ ! -d "${examples_dir}" ]]; then
  echo "ERROR: selfservice examples directory missing: ${examples_dir}" >&2
  exit 1
fi

scripts=(
  "submit.sh"
  "validate.sh"
  "normalize.sh"
  "diff.sh"
  "impact.sh"
  "plan.sh"
  "review.sh"
  "redact.sh"
)

for script in "${scripts[@]}"; do
  require_exec "${FABRIC_REPO_ROOT}/ops/selfservice/${script}"
done

if ! rg -n "selfservice submission is not allowed in CI" "${FABRIC_REPO_ROOT}/ops/selfservice/submit.sh" >/dev/null 2>&1; then
  echo "ERROR: selfservice submit must refuse CI" >&2
  exit 1
fi

if ! rg -n "plan-only mode" "${FABRIC_REPO_ROOT}/ops/selfservice/plan.sh" >/dev/null 2>&1; then
  echo "ERROR: selfservice plan guards missing" >&2
  exit 1
fi

if ! rg -n "selfservice/inbox/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  echo "ERROR: selfservice inbox must be gitignored" >&2
  exit 1
fi

if ! PROPOSAL_ID=example bash "${FABRIC_REPO_ROOT}/ops/selfservice/validate.sh" >/dev/null 2>&1; then
  echo "ERROR: selfservice example proposals failed validation" >&2
  exit 1
fi

echo "policy-selfservice: OK"
