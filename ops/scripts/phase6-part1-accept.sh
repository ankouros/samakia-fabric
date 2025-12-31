#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
marker_path="${FABRIC_REPO_ROOT}/acceptance/PHASE6_PART1_ACCEPTED.md"

run_make() {
  make -C "${FABRIC_REPO_ROOT}" "$@"
}

run_make consumers.validate
run_make consumers.ha.check
run_make consumers.disaster.check
run_make consumers.evidence
run_make policy.check

cat <<MARKER > "${marker_path}"
# Phase 6 Part 1 Acceptance Marker — Consumer Contract Validation

Phase: Phase 6 Part 1 — Consumer Contract Validation
Scope source: ROADMAP.md (Phase 6)

Acceptance statement:
Phase 6 Part 1 is ACCEPTED and LOCKED. Any further changes are regressions.

Assurance statement:
Consumer contracts validated; HA-ready and disaster-aware patterns enforced; no infrastructure deployed.

Repository:
- Commit: ${commit_hash}
- Timestamp (UTC): ${stamp}

Acceptance commands executed:
- make consumers.validate
- make consumers.ha.check
- make consumers.disaster.check
- make consumers.evidence
- make policy.check
- make phase6.part1.accept

Remediation ledger:
- REQUIRED-FIXES.md
MARKER

hash_value="$(sha256sum "${marker_path}" | awk '{print $1}')"

cat <<EOF_HASH >> "${marker_path}"

SHA256 (content excluding this line): ${hash_value}
EOF_HASH

printf "OK: wrote %s\n" "${marker_path}"
