#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
marker_path="${FABRIC_REPO_ROOT}/acceptance/PHASE7_ACCEPTED.md"

run_make() {
  make -C "${FABRIC_REPO_ROOT}" "$@"
}

run_make policy.check
run_make ai.runbook.check
run_make ai.safe.index.check
run_make phase7.entry.check

fixture="${FABRIC_REPO_ROOT}/ops/ai/plan-review/fixtures/plan.sample.txt"
if [[ ! -f "${fixture}" ]]; then
  echo "ERROR: plan review fixture missing: ${fixture}" >&2
  exit 1
fi

ENV="sample" bash "${FABRIC_REPO_ROOT}/ops/ai/plan-review/plan-review.sh" \
  --plan "${fixture}" --env "sample"

bash "${FABRIC_REPO_ROOT}/ops/scripts/safe-run.sh" policy.check --dry-run
bash "${FABRIC_REPO_ROOT}/ops/scripts/safe-run.sh" ai.runbook.check --dry-run

set +e
bash "${FABRIC_REPO_ROOT}/ops/ai/remediate/remediate.sh" --execute --target policy.check >/dev/null 2>&1
remediate_rc=$?
set -e
if [[ ${remediate_rc} -eq 0 ]]; then
  echo "ERROR: remediation executed without guards" >&2
  exit 1
fi

cat <<MARKER > "${marker_path}"
# Phase 7 Acceptance Marker — AI Operations Safety

Phase: Phase 7 — AI Operations Safety
Scope source: ROADMAP.md (Phase 7)

Acceptance statement:
Phase 7 is ACCEPTED and LOCKED. Any further changes are regressions.

Assurance statement:
AI operations are bounded; remediation is opt-in and audited; acceptance is read-only.

Repository:
- Commit: ${commit_hash}
- Timestamp (UTC): ${stamp}

Acceptance commands executed:
- make policy.check
- make ai.runbook.check
- make ai.safe.index.check
- make phase7.entry.check
- make phase7.accept

Synthetic guard validations:
- plan-review fixture processed
- safe-run dry-run executed
- remediation refusal enforced

Remediation ledger:
- REQUIRED-FIXES.md
MARKER

hash_value="$(sha256sum "${marker_path}" | awk '{print $1}')"

cat <<EOF_HASH >> "${marker_path}"

SHA256 (content excluding this line): ${hash_value}
EOF_HASH

echo "OK: wrote ${marker_path}"
