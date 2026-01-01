#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

SUBSTRATE_ROOT="${FABRIC_REPO_ROOT}/ops/substrate"
TENANTS_ROOT="${FABRIC_REPO_ROOT}/contracts/tenants/examples"
DR_TAXONOMY="${FABRIC_REPO_ROOT}/contracts/substrate/dr-testcases.yml"
EVIDENCE_ROOT="${FABRIC_REPO_ROOT}/evidence/tenants"

export SUBSTRATE_ROOT TENANTS_ROOT DR_TAXONOMY EVIDENCE_ROOT
