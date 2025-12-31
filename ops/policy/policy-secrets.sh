#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

run_gitleaks() {
  local source_dir="$1"
  gitleaks detect \
    --source "${source_dir}" \
    --no-banner \
    --redact \
    --exit-code 1
}

if command -v gitleaks >/dev/null 2>&1; then
  run_gitleaks "${FABRIC_REPO_ROOT}"
elif command -v pre-commit >/dev/null 2>&1; then
  pre-commit run gitleaks --all-files
else
  echo "ERROR: gitleaks not found and pre-commit unavailable (install one of them)." >&2
  exit 1
fi
