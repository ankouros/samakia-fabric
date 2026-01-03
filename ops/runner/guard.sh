#!/usr/bin/env bash
set -euo pipefail

_runner_normalize() {
  local mode="${RUNNER_MODE:-ci}"
  if [[ -z "${mode}" ]]; then
    mode="ci"
  fi
  case "${mode}" in
    ci|operator)
      :
      ;;
    *)
      echo "ERROR: invalid RUNNER_MODE='${mode}' (expected 'ci' or 'operator')." >&2
      return 2
      ;;
  esac
  RUNNER_MODE="${mode}"
  export RUNNER_MODE
}

_runner_is_ci_env() {
  [[ -n "${CI:-}" && "${CI}" != "0" ]]
}

require_ci_mode() {
  _runner_normalize || exit 2
  if _runner_is_ci_env && [[ "${RUNNER_MODE}" != "ci" ]]; then
    echo "ERROR: CI requires RUNNER_MODE=ci (non-interactive)." >&2
    exit 2
  fi
  if [[ "${RUNNER_MODE}" != "ci" ]]; then
    echo "ERROR: RUNNER_MODE must be ci for this script (non-interactive)." >&2
    exit 2
  fi
}

require_operator_mode() {
  _runner_normalize || exit 2
  if _runner_is_ci_env; then
    echo "ERROR: operator mode is forbidden in CI (RUNNER_MODE=operator)." >&2
    exit 2
  fi
  if [[ "${RUNNER_MODE}" != "operator" ]]; then
    echo "ERROR: RUNNER_MODE=operator is required for interactive usage." >&2
    exit 2
  fi
}

fail_if_interactive() {
  _runner_normalize || exit 2
  if _runner_is_ci_env || [[ "${RUNNER_MODE}" == "ci" ]]; then
    echo "ERROR: interactive prompts are forbidden in CI mode." >&2
    exit 2
  fi
}

print_runner_context() {
  _runner_normalize || exit 2
  local ci_state="0"
  if _runner_is_ci_env; then
    ci_state="1"
  fi
  echo "RUNNER_MODE=${RUNNER_MODE} CI=${ci_state} INTERACTIVE=${INTERACTIVE:-0}" >&2
}
