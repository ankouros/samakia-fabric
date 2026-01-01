#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

TENANT="${TENANT:-all}" SUBSTRATE_PROVIDER="postgres" \
  "${FABRIC_REPO_ROOT}/ops/substrate/substrate.sh" dr-dryrun
