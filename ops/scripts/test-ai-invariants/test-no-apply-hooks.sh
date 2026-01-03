#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

analysis_root="${FABRIC_REPO_ROOT}/ops/ai/analysis"
ops_entry="${FABRIC_REPO_ROOT}/ops/ai/ops.sh"

if rg -n --glob '*.sh' "\b(apply|rollback|execute|remediate)\b" \
  "${analysis_root}" "${ops_entry}" >/dev/null 2>&1; then
  echo "ERROR: AI analysis contains apply/rollback hooks" >&2
  exit 1
fi

echo "PASS: no apply/rollback hooks detected"
