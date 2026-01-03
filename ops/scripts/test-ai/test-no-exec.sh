#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

analysis_dir="${FABRIC_REPO_ROOT}/ops/ai/analysis"

if rg -n "terraform apply|ansible-playbook|kubectl|pveam|pct|qm" "${analysis_dir}" >/dev/null 2>&1; then
  echo "ERROR: AI analysis references execution tooling" >&2
  exit 1
fi

if rg -n "\bapply\b" "${analysis_dir}" >/dev/null 2>&1; then
  echo "ERROR: AI analysis contains apply references" >&2
  exit 1
fi

echo "PASS: no AI execution paths detected"
