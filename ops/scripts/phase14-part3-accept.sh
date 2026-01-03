#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker_part3="${acceptance_dir}/PHASE14_PART3_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase14.part3] ${label}"
  "$@"
}

extract_alerts_path() {
  awk '/alerts evidence written to/ {print $NF}' | tail -n 1
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
incident_id="INC-PHASE14-PART3-${stamp//[:]/}"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Alerts validate" make -C "${FABRIC_REPO_ROOT}" alerts.validate
run_step "Phase 14 Part 3 entry check" make -C "${FABRIC_REPO_ROOT}" phase14.part3.entry.check

alerts_output=$(ALERTS_ENABLE=0 ALERT_SINK=slack TENANT=canary WORKLOAD=sample \
  make -C "${FABRIC_REPO_ROOT}" alerts.deliver)
alerts_evidence_dir=$(printf '%s\n' "${alerts_output}" | extract_alerts_path)
if [[ -z "${alerts_evidence_dir}" ]]; then
  echo "ERROR: failed to capture alerts evidence path" >&2
  exit 1
fi

run_step "Incident open" env INCIDENT_ID="${incident_id}" TENANT=canary WORKLOAD=sample \
  SIGNAL_TYPE=slo SEVERITY=WARN OWNER=operator EVIDENCE_REFS="${alerts_evidence_dir}" \
  make -C "${FABRIC_REPO_ROOT}" incidents.open

run_step "Incident close" env INCIDENT_ID="${incident_id}" RESOLUTION_SUMMARY="Synthetic closure" \
  EVIDENCE_REFS="${alerts_evidence_dir}" make -C "${FABRIC_REPO_ROOT}" incidents.close

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$(${commit_hash_script})"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker_part3}" <<EOF_MARKER
# Phase 14 Part 3 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make alerts.validate
- make phase14.part3.entry.check
- ALERTS_ENABLE=0 ALERT_SINK=slack make alerts.deliver TENANT=canary WORKLOAD=sample
- make incidents.open INCIDENT_ID=${incident_id}
- make incidents.close INCIDENT_ID=${incident_id}

Result: PASS

Evidence:
- ${alerts_evidence_dir}
- evidence/incidents/${incident_id}

Statement:
Alerts and incidents are informational only; no automation was introduced.
EOF_MARKER

self_hash_part3="$(sha256sum "${marker_part3}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_part3}"
} >> "${marker_part3}"
sha256sum "${marker_part3}" | awk '{print $1}' > "${marker_part3}.sha256"
