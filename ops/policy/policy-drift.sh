#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_exec() {
  local path="$1"
  [[ -x "${path}" ]] || fail "missing or non-executable: ${path}"
}

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
}

require_exec "${FABRIC_REPO_ROOT}/ops/drift/detect.sh"
require_exec "${FABRIC_REPO_ROOT}/ops/drift/classify.sh"
require_exec "${FABRIC_REPO_ROOT}/ops/drift/summary.sh"
require_exec "${FABRIC_REPO_ROOT}/ops/drift/redact.sh"
require_exec "${FABRIC_REPO_ROOT}/ops/drift/compare/bindings.sh"
require_exec "${FABRIC_REPO_ROOT}/ops/drift/compare/capacity.sh"
require_exec "${FABRIC_REPO_ROOT}/ops/drift/compare/security.sh"
require_exec "${FABRIC_REPO_ROOT}/ops/drift/compare/availability.sh"

require_file "${FABRIC_REPO_ROOT}/docs/drift/overview.md"
require_file "${FABRIC_REPO_ROOT}/docs/drift/taxonomy.md"

if ! rg -n "make drift\\.detect" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  fail "cookbook missing drift.detect task"
fi
if ! rg -n "make drift\\.summary" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  fail "cookbook missing drift.summary task"
fi

if ! rg -n "^evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  fail ".gitignore must include evidence/"
fi
if ! rg -n "^artifacts/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  fail ".gitignore must include artifacts/"
fi

if ! rg -n "drift\\.detect" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1; then
  fail "pr-validate workflow missing drift.detect"
fi

echo "PASS: drift policy checks"
