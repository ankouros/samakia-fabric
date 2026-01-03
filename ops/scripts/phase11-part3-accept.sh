#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE11_PART3_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase11.part3] ${label}"
  "$@"
}

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Operator docs anti-drift" make -C "${FABRIC_REPO_ROOT}" docs.operator.check
run_step "Tenant validation" make -C "${FABRIC_REPO_ROOT}" tenants.validate
run_step "Tenant capacity validation" make -C "${FABRIC_REPO_ROOT}" tenants.capacity.validate TENANT=all
run_step "Substrate contracts" make -C "${FABRIC_REPO_ROOT}" substrate.contracts.validate
run_step "Capacity guard" make -C "${FABRIC_REPO_ROOT}" substrate.capacity.guard TENANT=all
run_step "Capacity evidence" make -C "${FABRIC_REPO_ROOT}" substrate.capacity.evidence TENANT=all
run_step "Phase 11 Part 3 entry check" make -C "${FABRIC_REPO_ROOT}" phase11.part3.entry.check

mkdir -p "${acceptance_dir}"
commit_hash="$("${FABRIC_REPO_ROOT}"/ops/scripts/git-commit-hash.sh 2>/dev/null || git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >"${marker}" <<EOF_MARKER
# Phase 11 Part 3 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- make tenants.validate
- make tenants.capacity.validate TENANT=all
- make substrate.contracts.validate
- make substrate.capacity.guard TENANT=all
- make substrate.capacity.evidence TENANT=all
- make phase11.part3.entry.check

Result: PASS

Statement:
Part 3 adds capacity guardrails; no infra mutation performed in acceptance.
EOF_MARKER

self_hash="$(sha256sum "${marker}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash}"
} >> "${marker}"
sha256sum "${marker}" | awk '{print $1}' > "${marker}.sha256"
