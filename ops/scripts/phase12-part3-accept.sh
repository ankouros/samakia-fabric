#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE12_PART3_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase12.part3] ${label}"
  "$@"
}

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Bindings validation" make -C "${FABRIC_REPO_ROOT}" bindings.validate TENANT=all
run_step "Bindings render" make -C "${FABRIC_REPO_ROOT}" bindings.render TENANT=all
run_step "Secrets inspect" make -C "${FABRIC_REPO_ROOT}" bindings.secrets.inspect TENANT=all
run_step "Bindings verify (offline)" make -C "${FABRIC_REPO_ROOT}" bindings.verify.offline TENANT=all
run_step "Phase 12 Part 3 entry check" make -C "${FABRIC_REPO_ROOT}" phase12.part3.entry.check

mkdir -p "${acceptance_dir}"
commit_hash="$("${FABRIC_REPO_ROOT}"/ops/scripts/git-commit-hash.sh 2>/dev/null || git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >"${marker}" <<EOF_MARKER
# Phase 12 Part 3 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make bindings.validate TENANT=all
- make bindings.render TENANT=all
- make bindings.secrets.inspect TENANT=all
- make bindings.verify.offline TENANT=all
- make phase12.part3.entry.check

Result: PASS

Statement:
Phase 12 Part 3 adds workload-side read-only binding verification. No substrate or workload mutation occurred; live mode remained disabled.
EOF_MARKER

self_hash="$(sha256sum "${marker}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash}"
} >> "${marker}"
sha256sum "${marker}" | awk '{print $1}' > "${marker}.sha256"
