#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  maint-window.sh --start <UTC ISO> --end <UTC ISO> [--max-minutes <n>]

Example:
  maint-window.sh --start 2025-01-01T00:00:00Z --end 2025-01-01T00:30:00Z
EOT
}

START=""
END=""
MAX_MINUTES="60"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start)
      START="${2:-}"
      shift 2
      ;;
    --end)
      END="${2:-}"
      shift 2
      ;;
    --max-minutes)
      MAX_MINUTES="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${START}" || -z "${END}" ]]; then
  echo "ERROR: --start and --end are required" >&2
  usage
  exit 2
fi

if ! [[ "${MAX_MINUTES}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --max-minutes must be an integer" >&2
  exit 2
fi

START="${START}" END="${END}" MAX_MINUTES="${MAX_MINUTES}" python3 - <<'PY'
import os
import sys
from datetime import datetime, timezone

def parse_iso(value: str) -> datetime:
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.fromisoformat(value).astimezone(timezone.utc)

start = parse_iso(os.environ["START"])
end = parse_iso(os.environ["END"])
max_minutes = int(os.environ["MAX_MINUTES"])

if end <= start:
    print("ERROR: maintenance window end must be after start", file=sys.stderr)
    sys.exit(1)

duration = (end - start).total_seconds() / 60.0
if duration > max_minutes:
    print(f"ERROR: maintenance window exceeds max duration ({duration:.1f}m > {max_minutes}m)", file=sys.stderr)
    sys.exit(1)

now = datetime.now(timezone.utc)
if now < start or now > end:
    print("ERROR: current UTC time is outside the maintenance window", file=sys.stderr)
    sys.exit(1)

print("OK: current UTC time is within maintenance window")
PY
