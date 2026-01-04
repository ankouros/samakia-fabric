#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"

if [[ "${RUNNER_MODE:-ci}" == "operator" ]]; then
  require_operator_mode
else
  require_ci_mode
fi


redaction_contract() {
  echo "${FABRIC_REPO_ROOT}/contracts/ai/indexing.yml"
}
