#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ -z "${INCIDENT_ID:-}" || -z "${UPDATE_SUMMARY:-}" ]]; then
  echo "ERROR: INCIDENT_ID and UPDATE_SUMMARY are required" >&2
  exit 2
fi

incident_root="${INCIDENT_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/incidents}"
incident_dir="${incident_root}/${INCIDENT_ID}"

if [[ ! -f "${incident_dir}/open.json" ]]; then
  echo "ERROR: open.json not found for incident ${INCIDENT_ID}" >&2
  exit 1
fi

updated_at="${UPDATED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
status="${STATUS:-investigating}"

update_dir="${incident_dir}/updates"
mkdir -p "${update_dir}"

UPDATE_PATH="${update_dir}/${updated_at}.json"

UPDATED_AT="${updated_at}" STATUS="${status}" python3 - "${incident_dir}/open.json" "${UPDATE_PATH}" <<'PY'
import json
import os
import sys
from pathlib import Path

open_path = Path(sys.argv[1])
update_path = Path(sys.argv[2])

base = json.loads(open_path.read_text())

payload = {
    "incident_id": base.get("incident_id"),
    "tenant": base.get("tenant"),
    "workload": base.get("workload"),
    "signal_type": base.get("signal_type"),
    "severity": base.get("severity"),
    "opened_at": base.get("opened_at"),
    "updated_at": os.environ["UPDATED_AT"],
    "status": os.environ["STATUS"],
    "owner": base.get("owner"),
    "evidence_refs": os.environ.get("EVIDENCE_REFS", "").split() or base.get("evidence_refs", []),
    "resolution_summary": os.environ["UPDATE_SUMMARY"],
    "event": "update",
    "notes": os.environ.get("UPDATE_NOTES"),
}

update_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

INCIDENT_PATH="${UPDATE_PATH}" bash "${FABRIC_REPO_ROOT}/ops/incidents/validate.sh"

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

echo "PASS: incident updated at ${UPDATE_PATH}"
