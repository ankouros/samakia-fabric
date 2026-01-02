#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  echo "usage: load.sh [--policy <path>]" >&2
}

policy_file="${POLICY_FILE:-${FABRIC_REPO_ROOT}/contracts/exposure/exposure-policy.yml}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy)
      policy_file="$2"
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

if [[ ! -f "${policy_file}" ]]; then
  echo "ERROR: policy file not found: ${policy_file}" >&2
  exit 1
fi

cat "${policy_file}"
