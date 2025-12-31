#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

runbook_dir="${FABRIC_REPO_ROOT}/ops/runbooks/ai"
format_file="${runbook_dir}/format.md"

if [[ ! -f "${format_file}" ]]; then
  echo "ERROR: runbook format missing: ${format_file}" >&2
  exit 1
fi

required=(
  "## Preconditions"
  "## Commands"
  "## Decision Points"
  "## Refusal Conditions"
  "## Evidence Artifacts"
  "## Exit Criteria"
)

shopt -s nullglob
runbooks=("${runbook_dir}"/*.md)
shopt -u nullglob

for file in "${runbooks[@]}"; do
  if [[ "${file}" == "${format_file}" ]]; then
    continue
  fi
  for header in "${required[@]}"; do
    if ! rg -n "^${header}$" "${file}" >/dev/null 2>&1; then
      echo "ERROR: ${file} missing required section: ${header}" >&2
      exit 1
    fi
  done
  echo "OK: ${file}"
done

if [[ ${#runbooks[@]} -le 1 ]]; then
  echo "ERROR: no AI runbooks found" >&2
  exit 1
fi

echo "OK: AI runbook format check passed"
