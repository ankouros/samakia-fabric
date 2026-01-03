#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
phase8_marker="${FABRIC_REPO_ROOT}/acceptance/PHASE8_PART2_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase8.part2] ${label}"
  "$@"
}

run_step "Phase 8 entry check" make phase8.entry.check
run_step "Policy gates" make policy.check
run_step "Register policy check" make images.vm.register.policy.check

if [[ "${TEMPLATE_VERIFY:-0}" == "1" ]]; then
  if [[ -z "${TEMPLATE_STORAGE:-}" || -z "${TEMPLATE_VM_ID:-}" || -z "${TEMPLATE_NODE:-}" || -z "${ENV:-}" ]]; then
    echo "ERROR: TEMPLATE_STORAGE, TEMPLATE_VM_ID, TEMPLATE_NODE, and ENV are required for TEMPLATE_VERIFY=1" >&2
    exit 1
  fi
  run_step "Template verify" make image.template.verify \
    IMAGE="${IMAGE:-ubuntu-24.04}" \
    VERSION="${VERSION:-v1}" \
    TEMPLATE_STORAGE="${TEMPLATE_STORAGE}" \
    TEMPLATE_VM_ID="${TEMPLATE_VM_ID}" \
    TEMPLATE_NODE="${TEMPLATE_NODE}" \
    ENV="${ENV}"
else
  echo "[phase8.part2] TEMPLATE_VERIFY not set; skipping template verification (read-only)"
fi

commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"

cat >"$phase8_marker" <<EOF_MARKER
# Phase 8 Part 2 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- make phase8.entry.check
- make policy.check
- make images.vm.register.policy.check
- make image.template.verify (only if TEMPLATE_VERIFY=1)

Result: PASS

Statement:
Template registration is guarded; acceptance is read-only; no VM provisioning performed.
EOF_MARKER

sha256sum "${phase8_marker}" | awk '{print $1}' > "${phase8_marker}.sha256"
