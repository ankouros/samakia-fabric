#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


qcow2=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --qcow2)
      qcow2="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
 done

if [[ -z "$qcow2" ]]; then
  echo "ERROR: --qcow2 is required" >&2
  exit 2
fi

if [[ ! -f "$qcow2" ]]; then
  echo "ERROR: qcow2 not found: $qcow2" >&2
  exit 1
fi

if ! command -v qemu-img >/dev/null 2>&1; then
  echo "ERROR: qemu-img is required for qcow2 validation" >&2
  exit 1
fi

info="$(qemu-img info "$qcow2")"

if ! printf '%s' "$info" | rg -q "file format: qcow2"; then
  echo "ERROR: qcow2 format check failed" >&2
  exit 1
fi

virtual_size_line="$(printf '%s' "$info" | rg "virtual size" || true)"
if [[ -z "$virtual_size_line" ]]; then
  echo "ERROR: unable to parse virtual size" >&2
  exit 1
fi

# Basic sanity: must be at least 2G
size_bytes=$(python3 - <<'PY'
import re
import sys
line = sys.argv[1]
match = re.search(r"\((\d+) bytes\)", line)
if not match:
    sys.exit(1)
print(match.group(1))
PY
"$virtual_size_line")

if [[ "$size_bytes" -lt 2000000000 ]]; then
  echo "ERROR: virtual size too small: ${size_bytes} bytes" >&2
  exit 1
fi
