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

if ! command -v guestfish >/dev/null 2>&1; then
  echo "ERROR: guestfish is required for offline inspection" >&2
  exit 1
fi

result=$(guestfish --ro -a "$qcow2" -i <<'EOF_GF'
is-file /etc/cloud/cloud.cfg
EOF_GF
)

if [[ "$result" != "true" ]]; then
  echo "ERROR: /etc/cloud/cloud.cfg not found in image" >&2
  exit 1
fi
