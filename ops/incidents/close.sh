#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ -z "${INCIDENT_ID:-}" || -z "${RESOLUTION_SUMMARY:-}" ]]; then
  echo "ERROR: INCIDENT_ID and RESOLUTION_SUMMARY are required" >&2
  exit 2
fi

incident_root="${INCIDENT_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/incidents}"
incident_dir="${incident_root}/${INCIDENT_ID}"

if [[ ! -f "${incident_dir}/open.json" ]]; then
  echo "ERROR: open.json not found for incident ${INCIDENT_ID}" >&2
  exit 1
fi

closed_at="${CLOSED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
status="${STATUS:-closed}"

CLOSED_AT="${closed_at}" STATUS="${status}" python3 - "${incident_dir}/open.json" "${incident_dir}/close.json" <<'PY'
import json
import os
import sys
from pathlib import Path

open_path = Path(sys.argv[1])
close_path = Path(sys.argv[2])

base = json.loads(open_path.read_text())

payload = {
    "incident_id": base.get("incident_id"),
    "tenant": base.get("tenant"),
    "workload": base.get("workload"),
    "signal_type": base.get("signal_type"),
    "severity": base.get("severity"),
    "opened_at": base.get("opened_at"),
    "updated_at": os.environ["CLOSED_AT"],
    "status": os.environ["STATUS"],
    "owner": base.get("owner"),
    "evidence_refs": os.environ.get("EVIDENCE_REFS", "").split() or base.get("evidence_refs", []),
    "resolution_summary": os.environ["RESOLUTION_SUMMARY"],
    "event": "close",
}

close_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

INCIDENT_PATH="${incident_dir}/close.json" bash "${FABRIC_REPO_ROOT}/ops/incidents/validate.sh"

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

echo "PASS: incident closed at ${incident_dir}/close.json"
