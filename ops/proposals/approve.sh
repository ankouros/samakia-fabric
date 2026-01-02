#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

proposal_id="${PROPOSAL_ID:-}"
if [[ -z "${proposal_id}" ]]; then
  echo "ERROR: set PROPOSAL_ID" >&2
  exit 1
fi
if [[ "${OPERATOR_APPROVE:-}" != "1" ]]; then
  echo "ERROR: set OPERATOR_APPROVE=1 to approve" >&2
  exit 1
fi
if [[ -z "${APPROVER_ID:-}" ]]; then
  echo "ERROR: set APPROVER_ID" >&2
  exit 1
fi

bash "${FABRIC_REPO_ROOT}/ops/proposals/validate.sh" PROPOSAL_ID="${proposal_id}"
STATUS=approved PROPOSAL_ID="${proposal_id}" APPROVER_ID="${APPROVER_ID}" DECISION_REASON="${APPROVE_REASON:-}" \
  EVIDENCE_SIGN="${EVIDENCE_SIGN:-}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  bash "${FABRIC_REPO_ROOT}/ops/proposals/decision.sh"
