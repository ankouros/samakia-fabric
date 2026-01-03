#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

phase8_marker="${FABRIC_REPO_ROOT}/acceptance/PHASE8_PART1_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase8.part1] ${label}"
  "$@"
}

run_step "Phase 8 entry check" make phase8.entry.check
run_step "Policy gates" make policy.check
run_step "Contract validation" make images.vm.validate.contracts

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash fabric-ci/scripts/lint.sh
run_step "Validate" bash fabric-ci/scripts/validate.sh

fixture="${QCOW2_FIXTURE_PATH:-}"
image="${IMAGE:-ubuntu-24.04}"
version="${VERSION:-v1}"

if [[ -n "$fixture" ]]; then
  run_step "Image validate" make image.validate IMAGE="$image" VERSION="$version" QCOW2="$fixture"
  run_step "Image validate evidence" make image.evidence.validate IMAGE="$image" VERSION="$version" QCOW2="$fixture"
else
  if [[ "${CI:-0}" == "1" ]]; then
    echo "[phase8.part1] QCOW2_FIXTURE_PATH not set; skipping artifact validation (CI tool-only mode)"
  else
    echo "ERROR: QCOW2_FIXTURE_PATH is required for local acceptance" >&2
    echo "Set QCOW2_FIXTURE_PATH or run with CI=1 for tool-only acceptance." >&2
    exit 1
  fi
fi

commit_hash="$(git -C "$FABRIC_REPO_ROOT" rev-parse HEAD)"

cat >"$phase8_marker" <<EOF_MARKER
# Phase 8 Part 1 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- make phase8.entry.check
- make policy.check
- make images.vm.validate.contracts
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make image.validate (only if QCOW2_FIXTURE_PATH set)
- make image.evidence.validate (only if QCOW2_FIXTURE_PATH set)

Result: PASS

Statement:
No Proxmox template registration and no VM provisioning performed.
EOF_MARKER

sha256sum "${phase8_marker}" | awk '{print $1}' > "${phase8_marker}.sha256"
