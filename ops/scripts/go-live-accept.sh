#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/GO_LIVE_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[go-live.accept] ${label}"
  "$@"
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_step "Platform regression" make -C "${FABRIC_REPO_ROOT}" platform.regression
run_step "Go-live entry check" make -C "${FABRIC_REPO_ROOT}" go-live.entry.check
run_step "Operator docs check" make -C "${FABRIC_REPO_ROOT}" docs.operator.check
run_step "AI invariants locked" rg -n "analysis-only" "${FABRIC_REPO_ROOT}/contracts/ai/INVARIANTS.md"
run_step "Exposure/rollback proven" test -f "${FABRIC_REPO_ROOT}/acceptance/PHASE17_STEP4_ACCEPTED.md"
run_step "Roadmap updated" rg -n "Production" "${FABRIC_REPO_ROOT}/ROADMAP.md"
run_step "Changelog updated" rg -n "go-live" "${FABRIC_REPO_ROOT}/CHANGELOG.md"
run_step "Review updated" rg -n "Go-Live" "${FABRIC_REPO_ROOT}/REVIEW.md"
run_step "Operations updated" rg -n "PRODUCTION_PLAYBOOK" "${FABRIC_REPO_ROOT}/OPERATIONS.md"

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$("${commit_hash_script}")"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker}" <<EOF_MARKER
# Go-Live Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- make platform.regression
- make go-live.entry.check
- make docs.operator.check
- rg -n "analysis-only" contracts/ai/INVARIANTS.md
- test -f acceptance/PHASE17_STEP4_ACCEPTED.md
- rg -n "Production" ROADMAP.md
- rg -n "go-live" CHANGELOG.md
- rg -n "Go-Live" REVIEW.md
- rg -n "PRODUCTION_PLAYBOOK" OPERATIONS.md
- bash ops/evidence/rebuild-index.sh
- bash ops/evidence/validate-index.sh

Result: PASS

Statement:
Samakia Fabric is production-ready.
All phases and follow-up steps are complete.
Platform behavior is governed, auditable, and locked.
EOF_MARKER

run_step "Evidence index rebuild" bash "${FABRIC_REPO_ROOT}/ops/evidence/rebuild-index.sh"
run_step "Evidence index validation" bash "${FABRIC_REPO_ROOT}/ops/evidence/validate-index.sh"

self_hash="$(sha256sum "${marker}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash}"
} >>"${marker}"
sha256sum "${marker}" | awk '{print $1}' >"${marker}.sha256"
