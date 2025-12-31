#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      dir="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: verify-evidence.sh --dir <evidence-dir>" >&2
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
 done

if [[ -z "$dir" ]]; then
  echo "ERROR: --dir is required" >&2
  exit 2
fi

if [[ ! -d "$dir" ]]; then
  echo "ERROR: evidence dir not found: $dir" >&2
  exit 1
fi

if [[ ! -f "$dir/manifest.sha256" ]]; then
  echo "ERROR: manifest.sha256 missing in $dir" >&2
  exit 1
fi

( cd "$dir" && sha256sum -c manifest.sha256 )

sig_file="${dir}/manifest.sha256.asc"
if [[ -f "$sig_file" ]]; then
  if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg is required to verify signature" >&2
    exit 1
  fi
  gpg --verify "$sig_file" "$dir/manifest.sha256"
  echo "PASS: signature verified"
else
  echo "PASS: no signature present"
fi

echo "PASS: evidence verified"
