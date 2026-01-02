#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

if [[ $# -ne 2 ]]; then
  echo "usage: redact.sh <input-json> <output-json>" >&2
  exit 2
fi

input="$1"
output="$2"

if [[ ! -f "${input}" ]]; then
  echo "ERROR: input not found: ${input}" >&2
  exit 1
fi

bash "${FABRIC_REPO_ROOT}/ops/substrate/common/redaction.sh" "${input}" "${output}"
