#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker_part6="${acceptance_dir}/PHASE12_PART6_ACCEPTED.md"
marker_phase12="${acceptance_dir}/PHASE12_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase12.part6] ${label}"
  "$@"
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readiness_dir="${FABRIC_REPO_ROOT}/evidence/release-readiness/phase12/${stamp}"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Operator docs anti-drift" make -C "${FABRIC_REPO_ROOT}" docs.operator.check
run_step "Phase 12 acceptance (read-only)" bash -c '
  CI=1 TENANT=all READINESS_STAMP="'"${stamp}"'" \
    make -C "'"${FABRIC_REPO_ROOT}"'" phase12.accept'
run_step "Phase 12 Part 6 entry check" make -C "${FABRIC_REPO_ROOT}" phase12.part6.entry.check

mkdir -p "${acceptance_dir}"
commit_hash="$("${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh" 2>/dev/null || git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"

cat >"${marker_part6}" <<EOF_MARKER
# Phase 12 Part 6 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- CI=1 TENANT=all READINESS_STAMP=${stamp} make phase12.accept
- make phase12.part6.entry.check

Result: PASS

Evidence:
- ${readiness_dir}/summary.md
- ${readiness_dir}/manifest.json
- ${readiness_dir}/manifest.sha256

Statement:
Phase 12 Part 6 closure complete. Release readiness packet generated and operator UX consolidated.
EOF_MARKER

self_hash_part6="$(sha256sum "${marker_part6}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_part6}"
} >> "${marker_part6}"
sha256sum "${marker_part6}" | awk '{print $1}' > "${marker_part6}.sha256"

cat >"${marker_phase12}" <<EOF_MARKER
# Phase 12 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- CI=1 TENANT=all READINESS_STAMP=${stamp} make phase12.accept
- make phase12.part6.entry.check

Result: PASS

Evidence:
- ${readiness_dir}/summary.md
- ${readiness_dir}/manifest.json
- ${readiness_dir}/manifest.sha256

Statement:
Phase 12 is complete; workload exposure is permitted under the documented controls.
EOF_MARKER

self_hash_phase12="$(sha256sum "${marker_phase12}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_phase12}"
} >> "${marker_phase12}"
sha256sum "${marker_phase12}" | awk '{print $1}' > "${marker_phase12}.sha256"
