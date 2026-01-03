#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker_part6="${acceptance_dir}/PHASE16_PART6_ACCEPTED.md"
marker_phase="${acceptance_dir}/PHASE16_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase16.part6] ${label}"
  "$@"
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "AI ops doctor" bash "${FABRIC_REPO_ROOT}/ops/ai/ops.sh" doctor
run_step "Phase 16 Part 6 entry check" make -C "${FABRIC_REPO_ROOT}" phase16.part6.entry.check

run_step "AI guardrail: no exec paths" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai/test-no-exec.sh"
run_step "AI guardrail: no external providers" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai/test-no-external-provider.sh"
run_step "AI guardrail: routing locked" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai/test-routing-locked.sh"
run_step "AI guardrail: MCP read-only" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai/test-mcp-readonly.sh"
run_step "AI guardrail: CI safety" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai/test-ci-safety.sh"
run_step "AI ops UX locked" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai/test-ai-ux.sh"
run_step "AI evidence index validation" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai/test-ai-evidence.sh"
run_step "AI capability guardrails" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai/test-ai-no-new-capabilities.sh"

run_step "Evidence index rebuild" bash "${FABRIC_REPO_ROOT}/ops/ai/evidence/rebuild-index.sh"
run_step "Evidence index determinism" bash "${FABRIC_REPO_ROOT}/ops/ai/evidence/validate-index.sh"

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$(${commit_hash_script})"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker_part6}" <<EOF_MARKER
# Phase 16 Part 6 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- bash ops/ai/ops.sh doctor
- make phase16.part6.entry.check
- ops/scripts/test-ai/test-no-exec.sh
- ops/scripts/test-ai/test-no-external-provider.sh
- ops/scripts/test-ai/test-routing-locked.sh
- ops/scripts/test-ai/test-mcp-readonly.sh
- ops/scripts/test-ai/test-ci-safety.sh
- ops/scripts/test-ai/test-ai-ux.sh
- ops/scripts/test-ai/test-ai-evidence.sh
- ops/scripts/test-ai/test-ai-no-new-capabilities.sh
- ops/ai/evidence/rebuild-index.sh
- ops/ai/evidence/validate-index.sh

Result: PASS

Statement:
Phase 16 AI-assisted analysis is complete and locked; AI is advisory only.
EOF_MARKER

self_hash_part6="$(sha256sum "${marker_part6}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_part6}"
} >>"${marker_part6}"
sha256sum "${marker_part6}" | awk '{print $1}' >"${marker_part6}.sha256"

cat >"${marker_phase}" <<EOF_PHASE
# Phase 16 Acceptance (Operations UX)

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- bash ops/ai/ops.sh doctor
- make phase16.part6.entry.check
- ops/scripts/test-ai/test-ai-ux.sh
- ops/scripts/test-ai/test-ai-evidence.sh
- ops/scripts/test-ai/test-ai-no-new-capabilities.sh
- ops/ai/evidence/rebuild-index.sh
- ops/ai/evidence/validate-index.sh

Result: PASS

Statement:
Phase 16 AI-assisted analysis is permanently advisory and evidence-bound.
EOF_PHASE

self_hash_phase="$(sha256sum "${marker_phase}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_phase}"
} >>"${marker_phase}"
sha256sum "${marker_phase}" | awk '{print $1}' >"${marker_phase}.sha256"
