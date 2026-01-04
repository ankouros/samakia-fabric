#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE17_STEP6_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase17.step6] ${label}"
  "$@"
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" env -u CI bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Phase 17 Step 6 entry check" make -C "${FABRIC_REPO_ROOT}" phase17.step6.entry.check
run_step "AI indexing offline" make -C "${FABRIC_REPO_ROOT}" ai.index.offline TENANT=platform SOURCE=docs
run_step "n8n workflow validation" make -C "${FABRIC_REPO_ROOT}" ai.n8n.validate

if CI=1 RUNNER_MODE=ci AI_INDEX_EXECUTE=1 AI_INDEX_REASON="ci-guard" QDRANT_ENABLE=1 OLLAMA_ENABLE=1 \
  make -C "${FABRIC_REPO_ROOT}" ai.index.live TENANT=platform SOURCE=docs >/dev/null 2>&1; then
  echo "ERROR: live indexing should be blocked in CI" >&2
  exit 1
else
  echo "PASS: live indexing refused in CI"
fi

run_step "Roadmap updated" rg -n "Step 6" "${FABRIC_REPO_ROOT}/ROADMAP.md"
run_step "Changelog updated" rg -n "Step 6" "${FABRIC_REPO_ROOT}/CHANGELOG.md"
run_step "Review updated" rg -n "Step 6" "${FABRIC_REPO_ROOT}/REVIEW.md"
run_step "Operations updated" rg -n "AI indexing" "${FABRIC_REPO_ROOT}/OPERATIONS.md"

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$("${commit_hash_script}")"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker}" <<EOF_MARKER
# Phase 17 Step 6 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make phase17.step6.entry.check
- make ai.index.offline TENANT=platform SOURCE=docs
- make ai.n8n.validate
- CI live indexing refusal check
- rg -n "Step 6" ROADMAP.md
- rg -n "Step 6" CHANGELOG.md
- rg -n "Step 6" REVIEW.md
- rg -n "AI indexing" OPERATIONS.md

Result: PASS

Statement:
No live indexing executed; no external calls; no remediation.
EOF_MARKER

self_hash="$(sha256sum "${marker}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash}"
} >>"${marker}"
sha256sum "${marker}" | awk '{print $1}' >"${marker}.sha256"
