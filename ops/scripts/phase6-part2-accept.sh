#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
marker_path="${FABRIC_REPO_ROOT}/acceptance/PHASE6_PART2_ACCEPTED.md"

run_make() {
  make -C "${FABRIC_REPO_ROOT}" "$@"
}

run_make policy.check
run_make phase6.entry.check
run_make consumers.validate
run_make consumers.ha.check
run_make consumers.disaster.check
run_make consumers.gameday.mapping.check
run_make consumers.gameday.dryrun
run_make consumers.evidence
run_make consumers.bundle
run_make consumers.bundle.check

cat <<MARKER > "${marker_path}"
# Phase 6 Part 2 Acceptance Marker — Consumer GameDay Wiring & Bundles

Phase: Phase 6 Part 2 — Consumer GameDay Wiring & Bundles
Scope source: ROADMAP.md (Phase 6)

Acceptance statement:
Phase 6 Part 2 is ACCEPTED and LOCKED. Any further changes are regressions.

Assurance statement:
No infrastructure mutated; GameDays were dry-run only; bundles and readiness packets are deterministic.

Repository:
- Commit: ${commit_hash}
- Timestamp (UTC): ${stamp}

Acceptance commands executed:
- make policy.check
- make phase6.entry.check
- make consumers.validate
- make consumers.ha.check
- make consumers.disaster.check
- make consumers.gameday.mapping.check
- make consumers.gameday.dryrun
- make consumers.evidence
- make consumers.bundle
- make consumers.bundle.check
- make phase6.part2.accept

Remediation ledger:
- REQUIRED-FIXES.md
MARKER

hash_value="$(sha256sum "${marker_path}" | awk '{print $1}')"

cat <<EOF_HASH >> "${marker_path}"

SHA256 (content excluding this line): ${hash_value}
EOF_HASH

printf "OK: wrote %s\n" "${marker_path}"
