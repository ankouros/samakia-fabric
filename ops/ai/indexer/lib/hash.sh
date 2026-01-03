#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOT'
Usage:
  hash.sh --file <path>
  hash.sh --string <value>
EOT
}

mode=""
value=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      mode="file"
      value="$2"
      shift 2
      ;;
    --string)
      mode="string"
      value="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${mode}" || -z "${value}" ]]; then
  usage
  exit 2
fi

if [[ "${mode}" == "file" ]]; then
  if [[ ! -f "${value}" ]]; then
    echo "ERROR: file not found: ${value}" >&2
    exit 1
  fi
  sha256sum "${value}" | awk '{print $1}'
else
  printf '%s' "${value}" | sha256sum | awk '{print $1}'
fi
