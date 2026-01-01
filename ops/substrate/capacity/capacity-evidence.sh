#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/env.sh"

TENANT="${TENANT:-all}"
CAPACITY_STAMP="${CAPACITY_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
CAPACITY_EVIDENCE_ROOT="${CAPACITY_EVIDENCE_ROOT:-${EVIDENCE_ROOT}}"

TENANT="${TENANT}" CAPACITY_STAMP="${CAPACITY_STAMP}" CAPACITY_EVIDENCE_ROOT="${CAPACITY_EVIDENCE_ROOT}" \
  bash "${FABRIC_REPO_ROOT}/ops/substrate/capacity/capacity-guard.sh"
