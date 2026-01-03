#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

repo_root="${FABRIC_REPO_ROOT}"

mapfile -t prompt_files < <(
  rg -l "^\\s*read\\b[^\\n]*(-p|-s)|^\\s*select\\b" "${FABRIC_REPO_ROOT}/ops" --glob "*.sh" || true
)

if [[ "${#prompt_files[@]}" -gt 0 ]]; then
  for file in "${prompt_files[@]}"; do
    if ! rg -n "require_operator_mode" "${file}" >/dev/null 2>&1; then
      fail "interactive prompt found without require_operator_mode: ${file}"
    fi
  done
fi

if RUNNER_MODE=ci CI=1 FABRIC_REPO_ROOT="${repo_root}" \
  bash "${repo_root}/ops/scripts/runner-env-install.sh" >/dev/null 2>&1; then
  fail "runner-env-install should fail fast in CI without --non-interactive"
fi

echo "PASS: no interactive prompts allowed in CI"
