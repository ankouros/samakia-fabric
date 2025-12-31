#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
marker_path="${FABRIC_REPO_ROOT}/acceptance/PHASE6_PART3_ACCEPTED.md"

run_make() {
  make -C "${FABRIC_REPO_ROOT}" "$@"
}

expect_fail() {
  set +e
  "$@"
  status=$?
  set -e
  if [[ "${status}" -eq 0 ]]; then
    echo "ERROR: expected failure but command succeeded: $*" >&2
    exit 1
  fi
}

run_make policy.check
run_make consumers.gameday.execute.policy.check
run_make phase6.entry.check

window_start="$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
window_end="$(date -u -d '5 minutes' +%Y-%m-%dT%H:%M:%SZ)"
window_out_start="$(date -u -d '10 minutes' +%Y-%m-%dT%H:%M:%SZ)"
window_out_end="$(date -u -d '20 minutes' +%Y-%m-%dT%H:%M:%SZ)"

bash "${FABRIC_REPO_ROOT}/ops/scripts/maint-window.sh" \
  --start "${window_start}" \
  --end "${window_end}" \
  --max-minutes 60

expect_fail bash "${FABRIC_REPO_ROOT}/ops/scripts/maint-window.sh" \
  --start "${window_out_start}" \
  --end "${window_out_end}" \
  --max-minutes 60

expect_fail env ENV="samakia-dev" GAMEDAY_EXECUTE=1 I_UNDERSTAND_MUTATION=1 \
  bash "${FABRIC_REPO_ROOT}/ops/consumers/disaster/consumer-gameday.sh" \
  --consumer "${FABRIC_REPO_ROOT}/contracts/consumers/kubernetes/ready.yml" \
  --testcase "gameday:vip-failover" --execute

expect_fail env ENV="samakia-prod" GAMEDAY_EXECUTE=1 I_UNDERSTAND_MUTATION=1 \
  bash "${FABRIC_REPO_ROOT}/ops/consumers/disaster/consumer-gameday.sh" \
  --consumer "${FABRIC_REPO_ROOT}/contracts/consumers/kubernetes/ready.yml" \
  --testcase "gameday:vip-failover" --execute

expect_fail env EVIDENCE_SIGN=1 EVIDENCE_SIGN_KEY="INVALID_KEY" \
  bash "${FABRIC_REPO_ROOT}/ops/consumers/disaster/consumer-gameday.sh" \
  --consumer "${FABRIC_REPO_ROOT}/contracts/consumers/cache/ready.yml" \
  --testcase "gameday:service-restart" --dry-run

cat <<MARKER > "${marker_path}"
# Phase 6 Part 3 Acceptance Marker — Controlled GameDay Execute Mode

Phase: Phase 6 Part 3 — Controlled GameDay Execute Mode
Scope source: ROADMAP.md (Phase 6)

Acceptance statement:
Phase 6 Part 3 is ACCEPTED and LOCKED. Any further changes are regressions.

Assurance statement:
Acceptance is dry-run only; no mutations performed; execute mode is guarded and allowlisted.

Repository:
- Commit: ${commit_hash}
- Timestamp (UTC): ${stamp}

Acceptance commands executed:
- make policy.check
- make consumers.gameday.execute.policy.check
- make phase6.entry.check
- make phase6.part3.accept

Synthetic guard validations:
- maint-window within bounds (PASS)
- maint-window outside bounds (FAIL expected)
- execute requires guards (FAIL expected)
- execute blocks prod (FAIL expected)
- signing path rejects invalid key (FAIL expected)

Remediation ledger:
- REQUIRED-FIXES.md
MARKER

hash_value="$(sha256sum "${marker_path}" | awk '{print $1}')"

cat <<EOF_HASH >> "${marker_path}"

SHA256 (content excluding this line): ${hash_value}
EOF_HASH

printf "OK: wrote %s\n" "${marker_path}"
