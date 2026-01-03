#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


routing_check="${FABRIC_REPO_ROOT}/ops/substrate/alert/validate-routing.sh"
if [[ ! -x "${routing_check}" ]]; then
  echo "ERROR: routing validator not found: ${routing_check}" >&2
  exit 1
fi

bash "${routing_check}"

format_dir="${FABRIC_REPO_ROOT}/ops/alerts/format"
formatters=("slack" "webhook" "email")

for fmt in "${formatters[@]}"; do
  if [[ ! -x "${format_dir}/${fmt}.sh" ]]; then
    echo "ERROR: format script missing: ${format_dir}/${fmt}.sh" >&2
    exit 1
  fi
done

if [[ ! -x "${FABRIC_REPO_ROOT}/ops/alerts/route.sh" ]]; then
  echo "ERROR: route.sh missing" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}" 2>/dev/null || true' EXIT

alert_in="${tmpdir}/alert.json"
cat >"${alert_in}" <<'JSON'
{
  "tenant": "canary",
  "workload": "sample",
  "env": "samakia-dev",
  "signal_type": "slo",
  "severity": "WARN",
  "severity_mapped": "info",
  "summary": "Synthetic alert for validation",
  "timestamp_utc": "2026-01-03T00:00:00Z",
  "evidence_ref": "evidence/alerts/canary/20260103T000000Z"
}
JSON

for fmt in "${formatters[@]}"; do
  out="${tmpdir}/${fmt}.json"
  IN_PATH="${alert_in}" OUT_PATH="${out}" bash "${format_dir}/${fmt}.sh"
  python3 - "${out}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    raise SystemExit("format output missing")
json.loads(path.read_text())
PY
  echo "PASS: alert format ${fmt}"
done

route_out="${tmpdir}/route.json"
TENANT="canary" ENV_ID="samakia-dev" PROVIDER="postgres" SEVERITY="WARN" ALERT_SINK="slack" OUT_PATH="${route_out}" \
  bash "${FABRIC_REPO_ROOT}/ops/alerts/route.sh"

python3 - "${route_out}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text())
required = {"emit", "suppressed", "delivery", "rate_limit", "quiet_hours"}
missing = [k for k in required if k not in payload]
if missing:
    raise SystemExit(f"route output missing keys: {missing}")
PY

echo "alert.validate: OK"
