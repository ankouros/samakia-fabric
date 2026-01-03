#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

redaction_contract() {
  echo "${FABRIC_REPO_ROOT}/contracts/ai/indexing.yml"
}
