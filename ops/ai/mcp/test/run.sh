#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${FABRIC_REPO_ROOT:-}" ]]; then
  FABRIC_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  export FABRIC_REPO_ROOT
fi

export RUNNER_MODE=ci

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

scripts=(
  "${FABRIC_REPO_ROOT}/ops/ai/mcp/test/test-repo.sh"
  "${FABRIC_REPO_ROOT}/ops/ai/mcp/test/test-evidence.sh"
  "${FABRIC_REPO_ROOT}/ops/ai/mcp/test/test-observability.sh"
  "${FABRIC_REPO_ROOT}/ops/ai/mcp/test/test-runbooks.sh"
  "${FABRIC_REPO_ROOT}/ops/ai/mcp/test/test-qdrant.sh"
)

for script in "${scripts[@]}"; do
  bash "${script}"
done

echo "PASS: MCP test harness"
