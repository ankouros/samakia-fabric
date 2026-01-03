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

require_file "${FABRIC_REPO_ROOT}/AI_OPERATIONS_POLICY.md"

if ! rg -n "ADR-0024" "${FABRIC_REPO_ROOT}/DECISIONS.md" >/dev/null 2>&1; then
  echo "ERROR: ADR-0024 not found in DECISIONS.md" >&2
  exit 1
fi

require_exec "${FABRIC_REPO_ROOT}/ops/ai/plan-review/plan-review.sh"
require_exec "${FABRIC_REPO_ROOT}/ops/ai/remediate/remediate.sh"
require_file "${FABRIC_REPO_ROOT}/ops/scripts/safe-index.yml"
require_exec "${FABRIC_REPO_ROOT}/ops/scripts/safe-run.sh"

if ! rg -n "^evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  echo "ERROR: evidence/ must be gitignored" >&2
  exit 1
fi

if ! rg -n "^artifacts/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  echo "ERROR: artifacts/ must be gitignored" >&2
  exit 1
fi

if rg -n "AI_REMEDIATE=1|GAMEDAY_EXECUTE=1|SAFE_RUN_EXECUTE=1" "${FABRIC_REPO_ROOT}/.github/workflows" >/dev/null 2>&1; then
  echo "ERROR: CI workflows must not enable execution flags" >&2
  exit 1
fi

remediate_script="${FABRIC_REPO_ROOT}/ops/ai/remediate/remediate.sh"
if ! rg -n "AI_REMEDIATE" "${remediate_script}" >/dev/null 2>&1; then
  echo "ERROR: remediation script missing AI_REMEDIATE guard" >&2
  exit 1
fi
if ! rg -n "I_UNDERSTAND_MUTATION" "${remediate_script}" >/dev/null 2>&1; then
  echo "ERROR: remediation script missing I_UNDERSTAND_MUTATION guard" >&2
  exit 1
fi
if ! rg -n "MAINT_WINDOW_START" "${remediate_script}" >/dev/null 2>&1; then
  echo "ERROR: remediation script missing maintenance window guard" >&2
  exit 1
fi

plan_review_script="${FABRIC_REPO_ROOT}/ops/ai/plan-review/plan-review.sh"
if rg -n "terraform apply" "${plan_review_script}" >/dev/null 2>&1; then
  echo "ERROR: plan review script must be read-only" >&2
  exit 1
fi

echo "OK: AI operations policy checks passed"
