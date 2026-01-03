#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ -z "${IN_PATH:-}" || -z "${OUT_PATH:-}" ]]; then
  echo "ERROR: IN_PATH and OUT_PATH are required" >&2
  exit 2
fi

python3 - "${IN_PATH}" "${OUT_PATH}" <<'PY'
import json
import sys
from pathlib import Path

inp = Path(sys.argv[1])
out = Path(sys.argv[2])

alert = json.loads(inp.read_text())
subject = f"[{alert.get('severity_mapped') or alert.get('severity')}] {alert.get('tenant')}/{alert.get('workload')}"

body_lines = [
    alert.get("summary") or "Alert",
    f"Signal: {alert.get('signal_type')}",
    f"Environment: {alert.get('env')}",
    f"Timestamp: {alert.get('timestamp_utc')}",
    f"Evidence: {alert.get('evidence_ref')}",
]

payload = {
    "subject": subject,
    "body": "\n".join([line for line in body_lines if line]),
}

out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
