#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE12_PART4_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase12.part4] ${label}"
  "$@"
}

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Bindings validation" make -C "${FABRIC_REPO_ROOT}" bindings.validate TENANT=all
run_step "Bindings render" make -C "${FABRIC_REPO_ROOT}" bindings.render TENANT=all
run_step "Tenant validation" make -C "${FABRIC_REPO_ROOT}" tenants.validate

run_step "Submit example proposals" bash -c '\
  PROPOSAL_ALLOW_EXISTING=1 \
  FILE="'"${FABRIC_REPO_ROOT}"'/examples/proposals/add-postgres-binding.yml" \
    bash "'"${FABRIC_REPO_ROOT}"'/ops/proposals/submit.sh"; \
  PROPOSAL_ALLOW_EXISTING=1 \
  FILE="'"${FABRIC_REPO_ROOT}"'/examples/proposals/increase-cache-capacity.yml" \
    bash "'"${FABRIC_REPO_ROOT}"'/ops/proposals/submit.sh"'

run_step "Proposal validation (examples)" make -C "${FABRIC_REPO_ROOT}" proposals.validate PROPOSAL_ID=example
run_step "Proposal review (binding)" make -C "${FABRIC_REPO_ROOT}" proposals.review PROPOSAL_ID=add-postgres-binding
run_step "Proposal review (capacity)" make -C "${FABRIC_REPO_ROOT}" proposals.review PROPOSAL_ID=increase-cache-capacity

run_step "Approval (binding example)" bash -c '\
  OPERATOR_APPROVE=1 APPROVER_ID="ops-acceptance" \
  PROPOSAL_ID=add-postgres-binding \
  bash "'"${FABRIC_REPO_ROOT}"'/ops/proposals/approve.sh"'

run_step "Apply guard check" bash -c '\
  if PROPOSAL_ID=add-postgres-binding \
    bash "'"${FABRIC_REPO_ROOT}"'/ops/proposals/apply.sh" >/dev/null 2>&1; then \
    echo "ERROR: apply guard missing"; exit 1; \
  fi'

run_step "Apply dry-run" bash -c '\
  PROPOSAL_ID=add-postgres-binding APPLY_DRYRUN=1 \
  bash "'"${FABRIC_REPO_ROOT}"'/ops/proposals/apply.sh"'

run_step "Phase 12 Part 4 entry check" make -C "${FABRIC_REPO_ROOT}" phase12.part4.entry.check

mkdir -p "${acceptance_dir}"
commit_hash="$("${FABRIC_REPO_ROOT}"/ops/scripts/git-commit-hash.sh 2>/dev/null || git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >"${marker}" <<EOF_MARKER
# Phase 12 Part 4 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make bindings.validate TENANT=all
- make bindings.render TENANT=all
- make tenants.validate
- proposals.submit (examples)
- make proposals.validate PROPOSAL_ID=example
- make proposals.review PROPOSAL_ID=add-postgres-binding
- make proposals.review PROPOSAL_ID=increase-cache-capacity
- proposals.approve PROPOSAL_ID=add-postgres-binding
- proposals.apply (guard check)
- proposals.apply (dry-run)
- make phase12.part4.entry.check

Result: PASS

Statement:
Phase 12 Part 4 enables optional self-service proposals with operator-controlled approval and apply. No autonomous apply occurred; all execution remained operator-controlled.
EOF_MARKER

self_hash="$(sha256sum "${marker}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash}"
} >> "${marker}"
sha256sum "${marker}" | awk '{print $1}' > "${marker}.sha256"
