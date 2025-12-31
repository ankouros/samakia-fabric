#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
marker="${FABRIC_REPO_ROOT}/acceptance/PHASE9_ACCEPTED.md"

run() {
  local label="$1"
  shift
  echo "[phase9] ${label}"
  "$@"
}

run "pre-commit" pre-commit run --all-files
run "lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run "validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run "policy" make policy.check
run "docs operator check" make docs.operator.check
run "phase9 entry check" make phase9.entry.check

commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"

cat >"${marker}" <<EOF_MARKER
# Phase 9 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- make phase9.entry.check

Summary: PASS

Statement: Phase 9 is documentation/UX/governance only; no infra mutation.
EOF_MARKER

sha256sum "${marker}" > "${marker}.sha256"
