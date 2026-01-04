#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE17_STEP7_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase17.step7] ${label}"
  "$@"
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" env -u CI bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "AI MCP doctor" make -C "${FABRIC_REPO_ROOT}" ai.mcp.doctor
run_step "AI MCP test harness" make -C "${FABRIC_REPO_ROOT}" ai.mcp.test
run_step "Phase 17 Step 7 entry check" make -C "${FABRIC_REPO_ROOT}" phase17.step7.entry.check

run_step "Roadmap updated" rg -n "Step 7" "${FABRIC_REPO_ROOT}/ROADMAP.md"
run_step "Changelog updated" rg -n "Step 7" "${FABRIC_REPO_ROOT}/CHANGELOG.md"
run_step "Review updated" rg -n "Step 7" "${FABRIC_REPO_ROOT}/REVIEW.md"
run_step "Operations updated" rg -n "MCP" "${FABRIC_REPO_ROOT}/OPERATIONS.md"

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$("${commit_hash_script}")"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker}" <<EOF_MARKER
# Phase 17 Step 7 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make ai.mcp.doctor
- make ai.mcp.test
- make phase17.step7.entry.check
- rg -n "Step 7" ROADMAP.md
- rg -n "Step 7" CHANGELOG.md
- rg -n "Step 7" REVIEW.md
- rg -n "MCP" OPERATIONS.md

Result: PASS

Statement:
MCP services are read-only and cannot act.
EOF_MARKER

self_hash="$(sha256sum "${marker}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash}"
} >>"${marker}"
sha256sum "${marker}" | awk '{print $1}' >"${marker}.sha256"
