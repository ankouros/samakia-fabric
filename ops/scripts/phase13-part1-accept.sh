#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE13_PART1_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase13.part1] ${label}"
  "$@"
}

ensure_signing_key() {
  if [[ -n "${EVIDENCE_SIGN_KEY:-}" ]]; then
    return 0
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg not available for prod signing" >&2
    exit 2
  fi
  export GNUPGHOME
  GNUPGHOME="$(mktemp -d)"
  gpg --batch --passphrase '' --quick-gen-key "phase13-ci@example.com" default default never >/dev/null 2>&1
  EVIDENCE_SIGN_KEY="$(gpg --list-secret-keys --with-colons | awk -F: '/^sec/ {print $5; exit}')"
  export EVIDENCE_SIGN_KEY
}

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Phase 13 Part 1 entry check" make -C "${FABRIC_REPO_ROOT}" phase13.part1.entry.check
run_step "Exposure plan (non-prod)" \
  bash -lc 'ENV=samakia-dev TENANT=canary WORKLOAD=sample make -C "'"${FABRIC_REPO_ROOT}"'" exposure.plan'

ensure_signing_key
window_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
window_end="$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)"
run_step "Exposure plan denied (prod)" \
  bash -lc 'ENV=samakia-prod TENANT=canary WORKLOAD=sample EXPECT_DENY=1 \
    EXPOSURE_SIGN=1 CHANGE_WINDOW_START='"${window_start}"' CHANGE_WINDOW_END='"${window_end}"' \
    EVIDENCE_SIGN_KEY='"${EVIDENCE_SIGN_KEY}"' make -C "'"${FABRIC_REPO_ROOT}"'" exposure.plan'

mkdir -p "${acceptance_dir}"
commit_hash="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash}" ]]; then
  commit_hash="$(${commit_hash})"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >"${marker}" <<EOF_MARKER
# Phase 13 Part 1 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make phase13.part1.entry.check
- make exposure.plan TENANT=canary WORKLOAD=sample ENV=samakia-dev
- make exposure.plan TENANT=canary WORKLOAD=sample ENV=samakia-prod (EXPECT_DENY=1, signing + change window)

Result: PASS

Statement:
Exposure planning only; no exposure was applied.
EOF_MARKER

sha256sum "${marker}" | awk '{print $1}' > "${marker}.sha256"
