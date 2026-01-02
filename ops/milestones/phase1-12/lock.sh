#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

require_cmd date
require_cmd git
require_cmd python3
require_cmd sha256sum

stamp="${MILESTONE_STAMP:-}"
packet_root="${MILESTONE_PACKET_ROOT:-${FABRIC_REPO_ROOT}/evidence/milestones/phase1-12}"

if [[ -z "${stamp}" ]]; then
  stamp="$(find "${packet_root}" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | LC_ALL=C sort | tail -n 1)"
fi

if [[ -z "${stamp}" ]]; then
  echo "ERROR: no milestone evidence packet found under ${packet_root}" >&2
  exit 1
fi

packet_dir="${packet_root}/${stamp}"
phase_results="${packet_dir}/phase-results.json"
commands_log="${packet_dir}/commands.log"

if [[ ! -f "${phase_results}" ]]; then
  echo "ERROR: phase-results.json missing at ${phase_results}" >&2
  exit 1
fi

if [[ ! -f "${commands_log}" ]]; then
  echo "ERROR: commands.log missing at ${commands_log}" >&2
  exit 1
fi

overall_status="$(python3 - "${phase_results}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
print(payload.get("overall_status", ""))
PY
)"

if [[ "${overall_status}" != "PASS" ]]; then
  echo "ERROR: milestone verification status is ${overall_status} (expected PASS)" >&2
  exit 1
fi

evidence_commit="$(python3 - "${phase_results}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
print(payload.get("commit", ""))
PY
)"

current_commit="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
if [[ -n "${evidence_commit}" && "${evidence_commit}" != "${current_commit}" ]]; then
  echo "ERROR: evidence commit ${evidence_commit} does not match current HEAD ${current_commit}" >&2
  exit 1
fi

mapfile -t commands < <(python3 - "${phase_results}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
commands = []
for section in payload.get("sections", []):
    for check in section.get("checks", []):
        cmd = check.get("command")
        if cmd:
            commands.append(cmd)

for cmd in commands:
    print(cmd)
PY
)

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
mkdir -p "${acceptance_dir}"
marker="${acceptance_dir}/MILESTONE_PHASE1_12_ACCEPTED.md"

lock_stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  echo "# Milestone Phase 1–12 Acceptance"
  echo
  echo "Timestamp (UTC): ${lock_stamp}"
  echo "Commit: ${current_commit}"
  echo
  echo "Evidence packet: ${packet_dir}"
  echo
  echo "Commands executed:"
  for cmd in "${commands[@]}"; do
    echo "- ${cmd}"
  done
  echo
  echo "Statement:"
  echo "Phase 1–12 verified, hardened, and safe for Phase 13."
} >"${marker}"

self_hash="$(sha256sum "${marker}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash}"
} >> "${marker}"

sha256sum "${marker}" | awk '{print $1}' > "${marker}.sha256"

echo "OK: wrote ${marker}"
