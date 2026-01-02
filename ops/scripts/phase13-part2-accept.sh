#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker_part2="${acceptance_dir}/PHASE13_PART2_ACCEPTED.md"
marker_phase13="${acceptance_dir}/PHASE13_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase13.part2] ${label}"
  "$@"
}

extract_evidence_path() {
  awk '/\/evidence\// {for (i=1; i<=NF; i++) if ($i ~ /\/evidence\//) print $i}' | tail -n 1
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Operator docs anti-drift" make -C "${FABRIC_REPO_ROOT}" docs.operator.check
run_step "Phase 13 Part 2 entry check" make -C "${FABRIC_REPO_ROOT}" phase13.part2.entry.check

plan_output=$(ENV=samakia-dev TENANT=canary WORKLOAD=sample make -C "${FABRIC_REPO_ROOT}" exposure.plan)
plan_dir=$(printf '%s
' "${plan_output}" | extract_evidence_path)
if [[ -z "${plan_dir}" ]]; then
  echo "ERROR: failed to capture plan evidence path" >&2
  exit 1
fi

approval_output=$(APPROVAL_ALLOW_CI=1 TENANT=canary WORKLOAD=sample ENV=samakia-dev \
  APPROVER_ID="phase13-ci" EXPOSE_REASON="phase13 part2 acceptance" PLAN_EVIDENCE_REF="${plan_dir}" \
  make -C "${FABRIC_REPO_ROOT}" exposure.approve)
approval_dir=$(printf '%s
' "${approval_output}" | extract_evidence_path)
if [[ -z "${approval_dir}" ]]; then
  echo "ERROR: failed to capture approval evidence path" >&2
  exit 1
fi

run_step "Approval validate" bash "${FABRIC_REPO_ROOT}/ops/exposure/approve/validate-approval.sh" --approval "${approval_dir}"

apply_output=$(APPROVAL_DIR="${approval_dir}" PLAN_EVIDENCE_REF="${plan_dir}" \
  TENANT=canary WORKLOAD=sample ENV=samakia-dev make -C "${FABRIC_REPO_ROOT}" exposure.apply)
apply_dir=$(printf '%s
' "${apply_output}" | extract_evidence_path)
if [[ -z "${apply_dir}" ]]; then
  echo "ERROR: failed to capture apply evidence path" >&2
  exit 1
fi

verify_output=$(TENANT=canary WORKLOAD=sample ENV=samakia-dev \
  make -C "${FABRIC_REPO_ROOT}" exposure.verify)
verify_dir=$(printf '%s
' "${verify_output}" | extract_evidence_path)
if [[ -z "${verify_dir}" ]]; then
  echo "ERROR: failed to capture verify evidence path" >&2
  exit 1
fi

rollback_output=$(ROLLBACK_REASON="phase13 acceptance rollback" ROLLBACK_REQUESTED_BY="phase13-ci" \
  TENANT=canary WORKLOAD=sample ENV=samakia-dev make -C "${FABRIC_REPO_ROOT}" exposure.rollback)
rollback_dir=$(printf '%s
' "${rollback_output}" | extract_evidence_path)
if [[ -z "${rollback_dir}" ]]; then
  echo "ERROR: failed to capture rollback evidence path" >&2
  exit 1
fi

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$(${commit_hash_script})"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker_part2}" <<EOF_MARKER
# Phase 13 Part 2 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- make phase13.part2.entry.check
- make exposure.plan TENANT=canary WORKLOAD=sample ENV=samakia-dev
- make exposure.approve TENANT=canary WORKLOAD=sample ENV=samakia-dev (synthetic approval)
- ops/exposure/approve/validate-approval.sh --approval ${approval_dir}
- make exposure.apply TENANT=canary WORKLOAD=sample ENV=samakia-dev (dry-run)
- make exposure.verify TENANT=canary WORKLOAD=sample ENV=samakia-dev
- make exposure.rollback TENANT=canary WORKLOAD=sample ENV=samakia-dev (dry-run)

Result: PASS

Evidence:
- ${plan_dir}
- ${approval_dir}
- ${apply_dir}
- ${verify_dir}
- ${rollback_dir}

Statement:
No autonomous exposure occurred; CI is dry-run only; no substrate provisioning.
EOF_MARKER

self_hash_part2="$(sha256sum "${marker_part2}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_part2}"
} >> "${marker_part2}"
sha256sum "${marker_part2}" | awk '{print $1}' > "${marker_part2}.sha256"

cat >"${marker_phase13}" <<EOF_MARKER
# Phase 13 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- make phase13.part2.entry.check
- make exposure.plan TENANT=canary WORKLOAD=sample ENV=samakia-dev
- make exposure.approve TENANT=canary WORKLOAD=sample ENV=samakia-dev (synthetic approval)
- ops/exposure/approve/validate-approval.sh --approval ${approval_dir}
- make exposure.apply TENANT=canary WORKLOAD=sample ENV=samakia-dev (dry-run)
- make exposure.verify TENANT=canary WORKLOAD=sample ENV=samakia-dev
- make exposure.rollback TENANT=canary WORKLOAD=sample ENV=samakia-dev (dry-run)

Result: PASS

Evidence:
- ${plan_dir}
- ${approval_dir}
- ${apply_dir}
- ${verify_dir}
- ${rollback_dir}

Statement:
Phase 13 is complete. Exposure remains operator-controlled, evidence-backed, and dry-run in CI.
No autonomous exposure occurred; no substrate provisioning.
EOF_MARKER

self_hash_phase13="$(sha256sum "${marker_phase13}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_phase13}"
} >> "${marker_phase13}"
sha256sum "${marker_phase13}" | awk '{print $1}' > "${marker_phase13}.sha256"
