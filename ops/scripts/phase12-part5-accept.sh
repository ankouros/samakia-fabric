#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE12_PART5_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase12.part5] ${label}"
  "$@"
}

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Drift detection (offline, non-blocking)" bash -c '
  TENANT=all DRIFT_OFFLINE=1 DRIFT_NON_BLOCKING=1 DRIFT_FAIL_ON=none DRIFT_REQUIRE_SIGN=0 \
    make -C "'"${FABRIC_REPO_ROOT}"'" drift.detect'
run_step "Tenant drift summaries" bash -c '
  TENANT=all make -C "'"${FABRIC_REPO_ROOT}"'" drift.summary'
run_step "Phase 12 Part 5 entry check" make -C "${FABRIC_REPO_ROOT}" phase12.part5.entry.check

mkdir -p "${acceptance_dir}"
commit_hash="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash}" ]]; then
  commit_hash="$(${commit_hash} 2>/dev/null)"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >"${marker}" <<EOF_MARKER
# Phase 12 Part 5 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- TENANT=all DRIFT_OFFLINE=1 DRIFT_NON_BLOCKING=1 DRIFT_FAIL_ON=none DRIFT_REQUIRE_SIGN=0 make drift.detect
- TENANT=all make drift.summary
- make phase12.part5.entry.check

Result: PASS

Statement:
Drift was detected and reported; no remediation or mutation occurred.
EOF_MARKER

self_hash="$(sha256sum "${marker}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash}"
} >> "${marker}"
sha256sum "${marker}" | awk '{print $1}' > "${marker}.sha256"
