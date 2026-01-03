#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

analysis_root="${FABRIC_REPO_ROOT}/ops/ai/analysis"
ops_entry="${FABRIC_REPO_ROOT}/ops/ai/ops.sh"

if rg -n "terraform apply|ansible-playbook|kubectl|pveam|pct|qm|safe-run|remediate\.sh|--execute" \
  "${analysis_root}" "${ops_entry}" >/dev/null 2>&1; then
  echo "ERROR: AI analysis references execution tooling" >&2
  exit 1
fi

echo "PASS: no AI execution paths detected"
