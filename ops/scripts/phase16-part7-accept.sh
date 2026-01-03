#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker_part7="${acceptance_dir}/PHASE16_PART7_ACCEPTED.md"
marker_phase="${acceptance_dir}/PHASE16_ACCEPTED.md"
policy_script="${FABRIC_REPO_ROOT}/ops/policy/policy-ai-phase-boundary.sh"

run_step() {
  local label="$1"
  shift
  echo "[phase16.part7] ${label}"
  "$@"
}

simulate_violation() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  # shellcheck disable=SC2317
  cleanup() {
    rm -rf "${tmp_dir}"
  }
  trap cleanup RETURN

  mkdir -p "${tmp_dir}/contracts" "${tmp_dir}/ops/ai" "${tmp_dir}/acceptance"
  cp -R "${FABRIC_REPO_ROOT}/contracts/ai" "${tmp_dir}/contracts/"
  cp -R "${FABRIC_REPO_ROOT}/ops/ai/mcp" "${tmp_dir}/ops/ai/"
  cp -R "${FABRIC_REPO_ROOT}/ops/ai/analysis" "${tmp_dir}/ops/ai/"
  cp "${FABRIC_REPO_ROOT}/ops/ai/ops.sh" "${tmp_dir}/ops/ai/ops.sh"
  cp "${FABRIC_REPO_ROOT}/ROADMAP.md" "${tmp_dir}/ROADMAP.md"
  cp "${FABRIC_REPO_ROOT}/DECISIONS.md" "${tmp_dir}/DECISIONS.md"
  cp -R "${FABRIC_REPO_ROOT}/acceptance" "${tmp_dir}/acceptance"

  python3 - "${tmp_dir}/contracts/ai/analysis.schema.json" <<'PY'
import json
import sys

path = sys.argv[1]
schema = json.load(open(path, "r", encoding="utf-8"))
enum = schema.get("properties", {}).get("analysis_type", {}).get("enum", [])
if "simulated_violation" not in enum:
    enum.append("simulated_violation")
    schema["properties"]["analysis_type"]["enum"] = enum
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(schema, handle, indent=2, sort_keys=True)
        handle.write("\n")
PY

  if FABRIC_REPO_ROOT="${tmp_dir}" bash "${policy_script}"; then
    echo "ERROR: policy-ai-phase-boundary.sh did not fail on simulated violation" >&2
    exit 1
  fi

  echo "PASS: policy blocked simulated expansion"
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Phase 16 Part 7 entry check" make -C "${FABRIC_REPO_ROOT}" phase16.part7.entry.check

run_step "AI invariant: no exec paths" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai-invariants/test-no-exec-paths.sh"
run_step "AI invariant: no apply hooks" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai-invariants/test-no-apply-hooks.sh"
run_step "AI invariant: no external providers" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai-invariants/test-no-external-ai.sh"
run_step "AI invariant: routing immutable" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai-invariants/test-routing-immutable.sh"
run_step "AI invariant: MCP read-only" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai-invariants/test-mcp-readonly.sh"
run_step "AI invariant: contracts locked" bash "${FABRIC_REPO_ROOT}/ops/scripts/test-ai-invariants/test-ai-contracts-locked.sh"
run_step "AI phase boundary policy" bash "${policy_script}"

run_step "Roadmap locked" rg -n "COMPLETED and LOCKED" "${FABRIC_REPO_ROOT}/ROADMAP.md"
run_step "Changelog updated" rg -n "Phase 16" "${FABRIC_REPO_ROOT}/CHANGELOG.md"
run_step "Review updated" rg -n "Phase 16" "${FABRIC_REPO_ROOT}/REVIEW.md"
run_step "Operations updated" rg -n -i "AI invariants" "${FABRIC_REPO_ROOT}/OPERATIONS.md"

run_step "Phase-boundary policy rejects simulated expansion" simulate_violation

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$(${commit_hash_script})"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker_part7}" <<EOF_MARKER
# Phase 16 Part 7 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make phase16.part7.entry.check
- ops/scripts/test-ai-invariants/test-no-exec-paths.sh
- ops/scripts/test-ai-invariants/test-no-apply-hooks.sh
- ops/scripts/test-ai-invariants/test-no-external-ai.sh
- ops/scripts/test-ai-invariants/test-routing-immutable.sh
- ops/scripts/test-ai-invariants/test-mcp-readonly.sh
- ops/scripts/test-ai-invariants/test-ai-contracts-locked.sh
- ops/policy/policy-ai-phase-boundary.sh
- rg -n "Phase 16.*LOCKED" ROADMAP.md
- rg -n "Phase 16" CHANGELOG.md
- rg -n "Phase 16" REVIEW.md
- rg -n "AI invariants" OPERATIONS.md
- simulated policy violation check

Result: PASS

Statement:
AI behavior is locked as an invariant; any future change requires a new phase.
EOF_MARKER

self_hash_part7="$(sha256sum "${marker_part7}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_part7}"
} >>"${marker_part7}"
sha256sum "${marker_part7}" | awk '{print $1}' >"${marker_part7}.sha256"

cat >"${marker_phase}" <<EOF_PHASE
# Phase 16 Acceptance (Invariant Lock)

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make phase16.part7.entry.check
- ops/scripts/test-ai-invariants/test-no-exec-paths.sh
- ops/scripts/test-ai-invariants/test-no-apply-hooks.sh
- ops/scripts/test-ai-invariants/test-no-external-ai.sh
- ops/scripts/test-ai-invariants/test-routing-immutable.sh
- ops/scripts/test-ai-invariants/test-mcp-readonly.sh
- ops/scripts/test-ai-invariants/test-ai-contracts-locked.sh
- ops/policy/policy-ai-phase-boundary.sh
- simulated policy violation check

Result: PASS

Statement:
AI-assisted analysis is permanently advisory; AI behavior is locked as an invariant and cannot act without a new phase.
EOF_PHASE

self_hash_phase="$(sha256sum "${marker_phase}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_phase}"
} >>"${marker_phase}"
sha256sum "${marker_phase}" | awk '{print $1}' >"${marker_phase}.sha256"
