#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE10_PART2_ACCEPTED.md"

tenant="project-birds"
env_name="samakia-dev"

run_step() {
  local label="$1"
  shift
  echo "[phase10.part2] ${label}"
  "$@"
}

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Operator docs anti-drift" make -C "${FABRIC_REPO_ROOT}" docs.operator.check
run_step "Tenant validation" make -C "${FABRIC_REPO_ROOT}" tenants.validate
run_step "Tenant execute policy check" make -C "${FABRIC_REPO_ROOT}" tenants.execute.policy.check
run_step "Tenant DR validation" make -C "${FABRIC_REPO_ROOT}" tenants.dr.validate
run_step "Phase 10 Part 2 entry check" make -C "${FABRIC_REPO_ROOT}" phase10.part2.entry.check
run_step "Tenant enablement plan (dry-run)" make -C "${FABRIC_REPO_ROOT}" tenants.plan TENANT="${tenant}" ENV="${env_name}" EXECUTE_REASON="acceptance-dry-run"
run_step "Tenant DR dry-run" make -C "${FABRIC_REPO_ROOT}" tenants.dr.run TENANT="${tenant}" ENV="${env_name}"

mkdir -p "${acceptance_dir}"
commit_hash="$("${FABRIC_REPO_ROOT}"/ops/scripts/git-commit-hash.sh 2>/dev/null || git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >"${marker}" <<EOF_MARKER
# Phase 10 Part 2 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- make tenants.validate
- make tenants.execute.policy.check
- make tenants.dr.validate
- make phase10.part2.entry.check
- make tenants.plan TENANT=${tenant} ENV=${env_name} EXECUTE_REASON=acceptance-dry-run
- make tenants.dr.run TENANT=${tenant} ENV=${env_name}

Result: PASS

Statement:
Phase 10 Part 2 is dry-run only; no infra mutation and no enabled.yml apply executed.
EOF_MARKER

sha256sum "${marker}" | awk '{print $1}' > "${marker}.sha256"
