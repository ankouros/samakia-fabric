#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

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
is-file /etc/samakia-image/pkg-manifest.txt
EOF_GF
)

if [[ "$result" != "true" ]]; then
  echo "ERROR: /etc/samakia-image/pkg-manifest.txt not found" >&2
  exit 1
fi
