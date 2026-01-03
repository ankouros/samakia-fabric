#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MAKEFILE="${ROOT_DIR}/Makefile"

if [[ ! -f "${MAKEFILE}" ]]; then
  echo "ERROR: Makefile not found" >&2
  exit 1
fi

require_target() {
  local target="$1"
  local pattern="^${target//./\\.}:"
  if ! rg -n "${pattern}" "${MAKEFILE}" >/dev/null 2>&1; then
    echo "ERROR: missing Makefile target: ${target}" >&2
    exit 1
  fi
}

targets=(
  "phase12.part1.entry.check"
  "phase12.part1.accept"
  "phase12.part2.entry.check"
  "phase12.part2.accept"
  "phase12.part3.entry.check"
  "phase12.part3.accept"
  "phase12.part4.entry.check"
  "phase12.part4.accept"
  "phase12.part5.entry.check"
  "phase12.part5.accept"
  "phase12.readiness.packet"
  "phase12.part6.entry.check"
  "phase12.part6.accept"
  "phase12.accept"
  "bindings.validate"
  "bindings.render"
  "bindings.secrets.inspect"
  "bindings.verify.offline"
  "drift.summary"
  "proposals.validate"
  "proposals.review"
)

for target in "${targets[@]}"; do
  require_target "${target}"
done

if ! rg -n "^evidence/" "${ROOT_DIR}/.gitignore" >/dev/null 2>&1; then
  echo "ERROR: evidence/ must be gitignored" >&2
  exit 1
fi

if ! rg -n "^artifacts/" "${ROOT_DIR}/.gitignore" >/dev/null 2>&1; then
  echo "ERROR: artifacts/ must be gitignored" >&2
  exit 1
fi

if rg -n "curl -k|--insecure|sslmode=disable" -S \
  --glob '!ops/scripts/phase2-1-entry-check.sh' \
  --glob '!ops/scripts/phase2-2-entry-check.sh' \
  --glob '!ops/milestones/phase1-12/verify.sh' \
  --glob '!ops/scripts/test-phase12/test-phase12-targets.sh' \
  "${ROOT_DIR}/ops" "${ROOT_DIR}/fabric-ci" "${ROOT_DIR}/Makefile" >/dev/null 2>&1; then
  echo "ERROR: insecure TLS flags detected in scripts" >&2
  exit 1
fi

echo "PASS: Phase 12 targets present"
