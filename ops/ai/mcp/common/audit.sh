#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

audit_root() {
  echo "${FABRIC_REPO_ROOT}/evidence/ai/mcp-audit"
}
