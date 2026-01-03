#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


file="${FILE:-${1:-}}"
if [[ -z "${file}" ]]; then
  echo "ERROR: set FILE=<proposal.yml>" >&2
  exit 1
fi
if [[ ! -f "${file}" ]]; then
  echo "ERROR: proposal file not found: ${file}" >&2
  exit 1
fi

read -r tenant_id proposal_id < <(PROPOSAL_PATH="${file}" python3 - <<'PY'
import os
import yaml
from pathlib import Path
path = Path(os.environ["PROPOSAL_PATH"])
data = yaml.safe_load(path.read_text())
if not isinstance(data, dict):
    raise SystemExit("invalid proposal: expected mapping")
print(data.get("tenant_id", ""), data.get("proposal_id", ""))
PY
)

if [[ -z "${tenant_id}" || -z "${proposal_id}" ]]; then
  echo "ERROR: proposal must include tenant_id and proposal_id" >&2
  exit 1
fi

inbox_dir="${FABRIC_REPO_ROOT}/proposals/inbox/${tenant_id}/${proposal_id}"
if [[ -e "${inbox_dir}" ]]; then
  if [[ "${PROPOSAL_ALLOW_EXISTING:-}" == "1" ]]; then
    printf 'OK: proposal already exists (skipped): %s\n' "${inbox_dir}"
    exit 0
  fi
  echo "ERROR: proposal already exists: ${inbox_dir}" >&2
  exit 1
fi

mkdir -p "${inbox_dir}"
cp "${file}" "${inbox_dir}/proposal.yml"
sha256sum "${inbox_dir}/proposal.yml" | awk '{print $1}' >"${inbox_dir}/checksum.sha256"

printf 'OK: proposal submitted to %s\n' "${inbox_dir}"
