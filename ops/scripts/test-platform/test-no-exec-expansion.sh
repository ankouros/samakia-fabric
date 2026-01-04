#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


forbidden_re='AUTO_APPLY|AUTO_EXECUTE|AUTONOMY_EXECUTE|AUTO_REMEDIATE|AUTO_REPAIR|AUTO_HEAL|AUTO_FIX|AUTO_DEPLOY'

if rg -n --glob '!ops/scripts/test-platform/**' "${forbidden_re}" \
  "${FABRIC_REPO_ROOT}/ops" \
  "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  echo "ERROR: forbidden auto-exec pattern detected" >&2
  rg -n --glob '!ops/scripts/test-platform/**' "${forbidden_re}" \
    "${FABRIC_REPO_ROOT}/ops" "${FABRIC_REPO_ROOT}/Makefile" || true
  exit 1
fi

echo "PASS: no forbidden auto-exec patterns detected"
