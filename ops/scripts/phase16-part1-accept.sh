#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker_part1="${acceptance_dir}/PHASE16_PART1_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase16.part1] ${label}"
  "$@"
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Operator docs check" make -C "${FABRIC_REPO_ROOT}" docs.operator.check
run_step "Phase 16 Part 1 entry check" make -C "${FABRIC_REPO_ROOT}" phase16.part1.entry.check

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$(${commit_hash_script})"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker_part1}" <<EOF_MARKER
# Phase 16 Part 1 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- make phase16.part1.entry.check

Result: PASS

Statement:
Phase 16 Part 1 adds an Ollama-only AI provider contract, deterministic routing policy,
read-only AI CLI entrypoints, and policy gates. No remediation or mutation paths were introduced.
EOF_MARKER

self_hash_part1="$(sha256sum "${marker_part1}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_part1}"
} >>"${marker_part1}"
sha256sum "${marker_part1}" | awk '{print $1}' >"${marker_part1}.sha256"
