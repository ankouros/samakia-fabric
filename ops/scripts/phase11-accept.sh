#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE11_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase11] ${label}"
  "$@"
}

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Operator docs anti-drift" make -C "${FABRIC_REPO_ROOT}" docs.operator.check
run_step "Tenant validation" make -C "${FABRIC_REPO_ROOT}" tenants.validate
run_step "Substrate contracts validation" make -C "${FABRIC_REPO_ROOT}" substrate.contracts.validate
run_step "Phase 11 entry check" make -C "${FABRIC_REPO_ROOT}" phase11.entry.check

mkdir -p "${acceptance_dir}"
commit_hash="$("${FABRIC_REPO_ROOT}"/ops/scripts/git-commit-hash.sh 2>/dev/null || git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >"${marker}" <<EOF_MARKER
# Phase 11 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- make tenants.validate
- make substrate.contracts.validate
- make phase11.entry.check

Result: PASS

Statement:
Phase 11 is design-only; no infrastructure mutation.
EOF_MARKER

sha256sum "${marker}" | awk '{print $1}' > "${marker}.sha256"
