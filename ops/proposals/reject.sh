#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


proposal_id="${PROPOSAL_ID:-}"
if [[ -z "${proposal_id}" ]]; then
  echo "ERROR: set PROPOSAL_ID" >&2
  exit 1
fi
if [[ "${CI:-0}" == "1" ]]; then
  echo "ERROR: proposal rejection is not allowed in CI" >&2
  exit 2
fi
if [[ "${OPERATOR_REJECT:-}" != "1" ]]; then
  echo "ERROR: set OPERATOR_REJECT=1 to reject" >&2
  exit 1
fi
if [[ -z "${APPROVER_ID:-}" ]]; then
  echo "ERROR: set APPROVER_ID" >&2
  exit 1
fi

STATUS=rejected PROPOSAL_ID="${proposal_id}" APPROVER_ID="${APPROVER_ID}" DECISION_REASON="${REJECT_REASON:-}" \
  EVIDENCE_SIGN="${EVIDENCE_SIGN:-}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  bash "${FABRIC_REPO_ROOT}/ops/proposals/decision.sh"

proposal_path=$(find "${FABRIC_REPO_ROOT}/proposals/inbox" -type f -name "proposal.yml" -path "*/${proposal_id}/*" 2>/dev/null | head -n1 || true)
if [[ -n "${proposal_path}" ]]; then
  tenant_id=$(python3 - <<'PY'
import sys
import yaml
from pathlib import Path
proposal = yaml.safe_load(Path(sys.argv[1]).read_text())
print(proposal.get("tenant_id", ""))
PY
"${proposal_path}")
  if [[ -z "${tenant_id}" ]]; then
    echo "ERROR: tenant_id missing in proposal for archive" >&2
    exit 1
  fi
  proposal_dir="$(dirname "${proposal_path}")"
  archive_dir="${FABRIC_REPO_ROOT}/proposals/archive/${tenant_id}/${proposal_id}"
  if [[ -e "${archive_dir}" ]]; then
    echo "ERROR: archive destination already exists: ${archive_dir}" >&2
    exit 1
  fi
  mkdir -p "$(dirname "${archive_dir}")"
  mv "${proposal_dir}" "${archive_dir}"
  echo "OK: archived rejected proposal to ${archive_dir}"
fi
