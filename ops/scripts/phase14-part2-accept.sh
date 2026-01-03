#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker_part2="${acceptance_dir}/PHASE14_PART2_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase14.part2] ${label}"
  "$@"
}

extract_evidence_path() {
  awk '/SLO evaluation written to/ {print $NF}' | tail -n 1
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Operator docs anti-drift" make -C "${FABRIC_REPO_ROOT}" docs.operator.check
run_step "Phase 14 Part 2 entry check" make -C "${FABRIC_REPO_ROOT}" phase14.part2.entry.check

run_step "SLO ingest (offline)" make -C "${FABRIC_REPO_ROOT}" slo.ingest.offline TENANT=all

real_output=$(TENANT=all make -C "${FABRIC_REPO_ROOT}" slo.evaluate)
real_evidence_dir=$(printf '%s\n' "${real_output}" | extract_evidence_path)
if [[ -z "${real_evidence_dir}" ]]; then
  echo "ERROR: failed to capture SLO evaluation evidence path" >&2
  exit 1
fi

run_step "SLO alert readiness rules" make -C "${FABRIC_REPO_ROOT}" slo.alerts.generate TENANT=all

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$(${commit_hash_script})"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker_part2}" <<EOF_MARKER
# Phase 14 Part 2 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- make phase14.part2.entry.check
- make slo.ingest.offline TENANT=all
- make slo.evaluate TENANT=all
- make slo.alerts.generate TENANT=all

Result: PASS

Evidence:
- ${real_evidence_dir}

Statement:
SLO evaluation only; no alert delivery or remediation enabled.
EOF_MARKER

self_hash_part2="$(sha256sum "${marker_part2}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_part2}"
} >> "${marker_part2}"
sha256sum "${marker_part2}" | awk '{print $1}' > "${marker_part2}.sha256"
