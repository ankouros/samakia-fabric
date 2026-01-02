#!/usr/bin/env bash
set -euo pipefail

redact_value() {
  local value="${1:-}"
  if [[ -z "${value}" ]]; then
    echo ""
    return
  fi
  local len=${#value}
  if [[ ${len} -le 4 ]]; then
    echo "***"
    return
  fi
  echo "${value:0:2}***${value: -2}"
}
