#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ -z "${INCIDENT_ID:-}" || -z "${TENANT:-}" || -z "${WORKLOAD:-}" || -z "${SIGNAL_TYPE:-}" || -z "${SEVERITY:-}" || -z "${OWNER:-}" ]]; then
  echo "ERROR: INCIDENT_ID, TENANT, WORKLOAD, SIGNAL_TYPE, SEVERITY, and OWNER are required" >&2
  exit 2
fi

if [[ -z "${EVIDENCE_REFS:-}" ]]; then
  echo "ERROR: EVIDENCE_REFS is required (space-separated list)" >&2
  exit 2
fi

incident_root="${INCIDENT_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/incidents}"
incident_dir="${incident_root}/${INCIDENT_ID}"
mkdir -p "${incident_dir}" "${incident_dir}/updates"

opened_at="${OPENED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
status="${STATUS:-open}"
resolution_summary="${RESOLUTION_SUMMARY:-pending}"

OPENED_AT="${opened_at}" STATUS="${status}" RESOLUTION_SUMMARY="${resolution_summary}" \
  python3 - "${incident_dir}/open.json" <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])

payload = {
    "incident_id": os.environ["INCIDENT_ID"],
    "tenant": os.environ["TENANT"],
    "workload": os.environ["WORKLOAD"],
    "signal_type": os.environ["SIGNAL_TYPE"],
    "severity": os.environ["SEVERITY"],
    "opened_at": os.environ["OPENED_AT"],
    "status": os.environ["STATUS"],
    "owner": os.environ["OWNER"],
    "evidence_refs": os.environ["EVIDENCE_REFS"].split(),
    "resolution_summary": os.environ["RESOLUTION_SUMMARY"],
    "event": "open",
}

path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

INCIDENT_PATH="${incident_dir}/open.json" bash "${FABRIC_REPO_ROOT}/ops/incidents/validate.sh"

(
  cd "${incident_dir}"
  find . -type f \
    ! -name "manifest.sha256" \
    ! -name "manifest.sha256.asc" \
    -print0 \
    | sort -z \
    | xargs -0 sha256sum > manifest.sha256
)

bash "${FABRIC_REPO_ROOT}/ops/substrate/common/signer.sh" "${incident_dir}"

echo "PASS: incident opened at ${incident_dir}"
