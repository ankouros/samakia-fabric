#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


require_exec() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: required executable missing: ${path}" >&2
    exit 1
  fi
}

scripts=(
  "${FABRIC_REPO_ROOT}/ops/incidents/open.sh"
  "${FABRIC_REPO_ROOT}/ops/incidents/update.sh"
  "${FABRIC_REPO_ROOT}/ops/incidents/close.sh"
  "${FABRIC_REPO_ROOT}/ops/incidents/validate.sh"
)

for script in "${scripts[@]}"; do
  require_exec "${script}"
done

if rg -n "(terraform|ansible-playbook|apply|remediate|self-heal|curl|wget|ssh)" "${FABRIC_REPO_ROOT}/ops/incidents" >/dev/null 2>&1; then
  echo "ERROR: incidents tooling must not invoke automation" >&2
  exit 1
fi

echo "policy-incidents: OK"
