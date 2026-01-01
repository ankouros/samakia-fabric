#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE11_PART2_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase11.part2] ${label}"
  "$@"
}

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Operator docs anti-drift" make -C "${FABRIC_REPO_ROOT}" docs.operator.check
run_step "Tenant validation" make -C "${FABRIC_REPO_ROOT}" tenants.validate
run_step "Substrate contracts" make -C "${FABRIC_REPO_ROOT}" substrate.contracts.validate
run_step "Substrate plan" make -C "${FABRIC_REPO_ROOT}" substrate.plan TENANT=all
run_step "Substrate DR dry-run" make -C "${FABRIC_REPO_ROOT}" substrate.dr.dryrun TENANT=all
run_step "Substrate verify" make -C "${FABRIC_REPO_ROOT}" substrate.verify TENANT=all
run_step "Phase 11 Part 2 entry check" make -C "${FABRIC_REPO_ROOT}" phase11.part2.entry.check

mkdir -p "${acceptance_dir}"
commit_hash="$("${FABRIC_REPO_ROOT}"/ops/scripts/git-commit-hash.sh 2>/dev/null || git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >"${marker}" <<EOF_MARKER
# Phase 11 Part 2 Acceptance

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
- make substrate.plan TENANT=all
- make substrate.dr.dryrun TENANT=all
- make substrate.verify TENANT=all
- make phase11.part2.entry.check

Result: PASS

Statement:
Acceptance is non-destructive; execution is opt-in only.
EOF_MARKER

self_hash="$(sha256sum "${marker}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash}"
} >> "${marker}"
sha256sum "${marker}" | awk '{print $1}' > "${marker}.sha256"
