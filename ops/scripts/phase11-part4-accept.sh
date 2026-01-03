#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE11_PART4_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase11.part4] ${label}"
  "$@"
}

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Tenant capacity validation" make -C "${FABRIC_REPO_ROOT}" tenants.capacity.validate TENANT=all
run_step "Substrate observe" make -C "${FABRIC_REPO_ROOT}" substrate.observe TENANT=all
run_step "Substrate observe compare" make -C "${FABRIC_REPO_ROOT}" substrate.observe.compare TENANT=all
run_step "Phase 11 Part 4 entry check" make -C "${FABRIC_REPO_ROOT}" phase11.part4.entry.check

mkdir -p "${acceptance_dir}"
commit_hash="$("${FABRIC_REPO_ROOT}"/ops/scripts/git-commit-hash.sh 2>/dev/null || git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >"${marker}" <<EOF_MARKER
# Phase 11 Part 4 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make tenants.capacity.validate TENANT=all
- make substrate.observe TENANT=all
- make substrate.observe.compare TENANT=all
- make phase11.part4.entry.check

Result: PASS

Statement:
Runtime observability is read-only; drift detection produces deterministic evidence. No infrastructure mutation occurred.
EOF_MARKER

self_hash="$(sha256sum "${marker}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash}"
} >> "${marker}"
sha256sum "${marker}" | awk '{print $1}' > "${marker}.sha256"
