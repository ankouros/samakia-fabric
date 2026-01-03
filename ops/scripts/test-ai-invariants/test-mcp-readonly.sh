#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


handlers=(
  "${FABRIC_REPO_ROOT}/ops/ai/mcp/repo/handlers.sh"
  "${FABRIC_REPO_ROOT}/ops/ai/mcp/evidence/handlers.sh"
  "${FABRIC_REPO_ROOT}/ops/ai/mcp/observability/handlers.sh"
  "${FABRIC_REPO_ROOT}/ops/ai/mcp/runbooks/handlers.sh"
  "${FABRIC_REPO_ROOT}/ops/ai/mcp/qdrant/handlers.sh"
)

for handler in "${handlers[@]}"; do
  if [[ ! -f "${handler}" ]]; then
    echo "ERROR: missing MCP handler: ${handler}" >&2
    exit 1
  fi
  actions="$(bash -lc "source '${handler}'; mcp_routes_json")"
  if ! printf '%s' "${actions}" | python3 -c '
import json
import sys
payload = json.load(sys.stdin)
verbs = payload.get("actions", [])
for verb in verbs:
    lower = verb.lower()
    if any(word in lower for word in ("write", "delete", "update", "create", "apply", "exec", "upsert")):
        raise SystemExit(1)
print("ok")
'; then
    echo "ERROR: MCP actions include write verbs in ${handler}" >&2
    exit 1
  fi

done

echo "PASS: MCP endpoints are read-only"
