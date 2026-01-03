#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

proposal_id="${PROPOSAL_ID:-}"
file_override="${FILE:-}"

resolve_file() {
  local id="$1"
  local file="$2"
  if [[ -n "${file}" ]]; then
    printf '%s' "${file}"
    return
  fi
  if [[ -z "${id}" ]]; then
    echo ""; return
  fi
  local inbox
  inbox=$(find "${FABRIC_REPO_ROOT}/selfservice/inbox" -type f -name "proposal.yml" -path "*/${id}/*" 2>/dev/null | head -n1 || true)
  if [[ -n "${inbox}" ]]; then
    printf '%s' "${inbox}"
    return
  fi
  if [[ -f "${FABRIC_REPO_ROOT}/examples/selfservice/${id}.yml" ]]; then
    printf '%s' "${FABRIC_REPO_ROOT}/examples/selfservice/${id}.yml"
    return
  fi
  echo ""
}

proposal_path="$(resolve_file "${proposal_id}" "${file_override}")"
if [[ -z "${proposal_path}" || ! -f "${proposal_path}" ]]; then
  echo "ERROR: proposal file not found" >&2
  exit 1
fi

out_file="${OUT_FILE:-}"

normalized=$(PROPOSAL_PATH="${proposal_path}" python3 - <<'PY'
import json
import os
from pathlib import Path
import yaml

proposal_path = Path(os.environ["PROPOSAL_PATH"])
proposal = yaml.safe_load(proposal_path.read_text())
if not isinstance(proposal, dict):
    raise SystemExit("invalid proposal: expected mapping")
print(json.dumps(proposal, indent=2, sort_keys=True))
PY
)

if [[ -n "${out_file}" ]]; then
  mkdir -p "$(dirname "${out_file}")"
  printf '%s\n' "${normalized}" >"${out_file}"
else
  printf '%s\n' "${normalized}"
fi
