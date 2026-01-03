#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

if rg -n "openai|anthropic|gemini|cohere|api\.openai" "${FABRIC_REPO_ROOT}/contracts/ai" "${FABRIC_REPO_ROOT}/ops/ai" "${FABRIC_REPO_ROOT}/docs/ai" >/dev/null 2>&1; then
  echo "ERROR: external AI provider reference found" >&2
  exit 1
fi

echo "PASS: no external AI providers referenced"
