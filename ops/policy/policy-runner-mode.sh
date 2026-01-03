#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


fail() {
  echo "ERROR: $*" >&2
  exit 1
}

mapfile -t scripts < <(rg --files -g "*.sh" "${FABRIC_REPO_ROOT}/ops" | sort)

for script in "${scripts[@]}"; do
  if [[ "${script}" == "${FABRIC_REPO_ROOT}/ops/runner/guard.sh" ]]; then
    continue
  fi
  if ! rg -n "ops/runner/guard.sh" "${script}" >/dev/null 2>&1; then
    fail "runner guard not sourced: ${script}"
  fi
  if ! rg -n "require_(ci|operator)_mode" "${script}" >/dev/null 2>&1; then
    fail "runner mode not declared (require_ci_mode/require_operator_mode): ${script}"
  fi

done

mapfile -t prompt_files < <(
  rg -l "^\\s*read\\b[^\\n]*(-p|-s)|^\\s*select\\b" "${FABRIC_REPO_ROOT}/ops" --glob "*.sh" || true
)

for script in "${prompt_files[@]}"; do
  if [[ "${script}" == "${FABRIC_REPO_ROOT}/ops/runner/guard.sh" ]]; then
    continue
  fi
  if ! rg -n "require_operator_mode" "${script}" >/dev/null 2>&1; then
    fail "interactive prompt without require_operator_mode: ${script}"
  fi

done

if ! rg -n "^RUNNER_MODE \\?= ci" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  fail "Makefile must default RUNNER_MODE ?= ci"
fi

if ! rg -n "^export RUNNER_MODE" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  fail "Makefile must export RUNNER_MODE"
fi

echo "PASS: runner mode policy enforced"
