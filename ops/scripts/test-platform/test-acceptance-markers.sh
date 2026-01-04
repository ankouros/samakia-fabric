#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


required=(
  "acceptance/PHASE0_ACCEPTED.md"
  "acceptance/PHASE1_ACCEPTED.md"
  "acceptance/PHASE2_ACCEPTED.md"
  "acceptance/PHASE2_1_ACCEPTED.md"
  "acceptance/PHASE2_2_ACCEPTED.md"
  "acceptance/PHASE3_PART1_ACCEPTED.md"
  "acceptance/PHASE3_PART2_ACCEPTED.md"
  "acceptance/PHASE3_PART3_ACCEPTED.md"
  "acceptance/PHASE4_ACCEPTED.md"
  "acceptance/PHASE5_ACCEPTED.md"
  "acceptance/PHASE6_PART1_ACCEPTED.md"
  "acceptance/PHASE6_PART2_ACCEPTED.md"
  "acceptance/PHASE6_PART3_ACCEPTED.md"
  "acceptance/PHASE7_ACCEPTED.md"
  "acceptance/PHASE8_PART1_ACCEPTED.md"
  "acceptance/PHASE8_PART1_1_ACCEPTED.md"
  "acceptance/PHASE8_PART1_2_ACCEPTED.md"
  "acceptance/PHASE8_PART2_ACCEPTED.md"
  "acceptance/PHASE8_3_ACCEPTED.md"
  "acceptance/PHASE9_ACCEPTED.md"
  "acceptance/PHASE10_PART1_ACCEPTED.md"
  "acceptance/PHASE10_PART2_ACCEPTED.md"
  "acceptance/PHASE11_PART1_ACCEPTED.md"
  "acceptance/PHASE11_PART2_ACCEPTED.md"
  "acceptance/PHASE11_PART3_ACCEPTED.md"
  "acceptance/PHASE11_PART4_ACCEPTED.md"
  "acceptance/PHASE11_PART5_ROUTING_ACCEPTED.md"
  "acceptance/PHASE11_HARDENING_ACCEPTED.md"
  "acceptance/PHASE11_HARDENING_JSON_ACCEPTED.md"
  "acceptance/PHASE11_ACCEPTED.md"
  "acceptance/PHASE12_PART1_ACCEPTED.md"
  "acceptance/PHASE12_PART2_ACCEPTED.md"
  "acceptance/PHASE12_PART3_ACCEPTED.md"
  "acceptance/PHASE12_PART4_ACCEPTED.md"
  "acceptance/PHASE12_PART5_ACCEPTED.md"
  "acceptance/PHASE12_PART6_ACCEPTED.md"
  "acceptance/PHASE12_ACCEPTED.md"
  "acceptance/PHASE13_PART1_ACCEPTED.md"
  "acceptance/PHASE13_PART2_ACCEPTED.md"
  "acceptance/PHASE13_ACCEPTED.md"
  "acceptance/PHASE14_PART1_ACCEPTED.md"
  "acceptance/PHASE14_PART2_ACCEPTED.md"
  "acceptance/PHASE14_PART3_ACCEPTED.md"
  "acceptance/PHASE15_PART1_ACCEPTED.md"
  "acceptance/PHASE15_PART2_ACCEPTED.md"
  "acceptance/PHASE15_PART3_ACCEPTED.md"
  "acceptance/PHASE15_PART4_ACCEPTED.md"
  "acceptance/PHASE15_ACCEPTED.md"
  "acceptance/PHASE16_PART1_ACCEPTED.md"
  "acceptance/PHASE16_PART2_ACCEPTED.md"
  "acceptance/PHASE16_PART3_ACCEPTED.md"
  "acceptance/PHASE16_PART4_ACCEPTED.md"
  "acceptance/PHASE16_PART5_ACCEPTED.md"
  "acceptance/PHASE16_PART6_ACCEPTED.md"
  "acceptance/PHASE16_PART7_ACCEPTED.md"
  "acceptance/PHASE16_ACCEPTED.md"
  "acceptance/PHASE17_STEP2_ACCEPTED.md"
  "acceptance/PHASE17_STEP3_ACCEPTED.md"
  "acceptance/PHASE17_STEP4_ACCEPTED.md"
  "acceptance/PHASE17_STEP5_ACCEPTED.md"
  "acceptance/PHASE17_STEP6_ACCEPTED.md"
  "acceptance/PHASE17_STEP7_ACCEPTED.md"
  "acceptance/INTERNAL_POSTGRES_PATRONI_ACCEPTED.md"
  "acceptance/MILESTONE_PHASE1_12_ACCEPTED.md"
)

if [[ "${GO_LIVE_REQUIRED:-0}" == "1" ]]; then
  required+=("acceptance/GO_LIVE_ACCEPTED.md")
fi

missing=0
for marker in "${required[@]}"; do
  if [[ ! -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
    echo "ERROR: missing acceptance marker: ${marker}" >&2
    missing=1
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  exit 1
fi

echo "PASS: acceptance markers present"
