#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

if [[ -n "${MAINT_WINDOW_START:-}" || -n "${MAINT_WINDOW_END:-}" ]]; then
  echo "INFO: change window enforcement is not enabled in Phase 11 Part 1"
fi
