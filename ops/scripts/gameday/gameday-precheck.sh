#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


check_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: missing required file: ${path}" >&2
    exit 1
  fi
}

check_file "${FABRIC_REPO_ROOT}/acceptance/PHASE3_ENTRY_CHECKLIST.md"
check_file "${FABRIC_REPO_ROOT}/acceptance/PHASE3_PART1_ACCEPTED.md"
check_file "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md"

if ! grep -q "Phase 3 entry status: READY" "${FABRIC_REPO_ROOT}/acceptance/PHASE3_ENTRY_CHECKLIST.md"; then
  echo "ERROR: Phase 3 entry is not READY; check acceptance/PHASE3_ENTRY_CHECKLIST.md" >&2
  exit 1
fi

if grep -q "Resolution status: **OPEN**" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md"; then
  echo "ERROR: REQUIRED-FIXES.md contains OPEN items." >&2
  exit 1
fi

if grep -q "Status: OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md"; then
  echo "ERROR: REQUIRED-FIXES.md contains OPEN items." >&2
  exit 1
fi

# SDN stability (read-only) if targets exist
if grep -q "^dns.sdn.accept" "${FABRIC_REPO_ROOT}/Makefile"; then
  ENV=samakia-dns make -s dns.sdn.accept
fi
if grep -q "^minio.sdn.accept" "${FABRIC_REPO_ROOT}/Makefile"; then
  ENV=samakia-minio make -s minio.sdn.accept
fi
if grep -q "^shared.sdn.accept" "${FABRIC_REPO_ROOT}/Makefile"; then
  ENV=samakia-shared make -s shared.sdn.accept
fi

echo "PASS: GameDay precheck complete"
