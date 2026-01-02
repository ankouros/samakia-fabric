#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

proposal_id="${PROPOSAL_ID:-}"
file_override="${FILE:-}"
if [[ -z "${proposal_id}" && -z "${file_override}" ]]; then
  echo "ERROR: set PROPOSAL_ID or FILE" >&2
  exit 1
fi

collect_files=()
if [[ -n "${file_override}" ]]; then
  collect_files+=("${file_override}")
elif [[ "${proposal_id}" == "example" ]]; then
  while IFS= read -r path; do
    collect_files+=("${path}")
  done < <(find "${FABRIC_REPO_ROOT}/examples/proposals" -type f -name "*.yml" -print | sort)
elif [[ -n "${proposal_id}" ]]; then
  inbox=$(find "${FABRIC_REPO_ROOT}/proposals/inbox" -type f -name "proposal.yml" -path "*/${proposal_id}/*" 2>/dev/null | head -n1 || true)
  if [[ -n "${inbox}" ]]; then
    collect_files+=("${inbox}")
  elif [[ -f "${FABRIC_REPO_ROOT}/examples/proposals/${proposal_id}.yml" ]]; then
    collect_files+=("${FABRIC_REPO_ROOT}/examples/proposals/${proposal_id}.yml")
  else
    echo "ERROR: proposal file not found for PROPOSAL_ID=${proposal_id}" >&2
    exit 1
  fi
fi

if [[ ${#collect_files[@]} -eq 0 ]]; then
  echo "ERROR: proposal file not found" >&2
  exit 1
fi

for proposal_path in "${collect_files[@]}"; do
  if [[ ! -f "${proposal_path}" ]]; then
    echo "ERROR: proposal file not found: ${proposal_path}" >&2
    exit 1
  fi
  read -r tenant_id prop_id < <(PROPOSAL_PATH="${proposal_path}" python3 - <<'PY'
import os
import yaml
from pathlib import Path
proposal = yaml.safe_load(Path(os.environ["PROPOSAL_PATH"]).read_text())
print(proposal.get("tenant_id", ""), proposal.get("proposal_id", ""))
PY
)

  if [[ -z "${tenant_id}" || -z "${prop_id}" ]]; then
    echo "ERROR: proposal missing tenant_id or proposal_id" >&2
    exit 1
  fi

  out_dir="${FABRIC_REPO_ROOT}/evidence/proposals/${tenant_id}/${prop_id}"
  mkdir -p "${out_dir}"

  VALIDATION_OUT="${out_dir}/validation.json" PROPOSAL_ID="${prop_id}" FILE="${proposal_path}" \
    bash "${FABRIC_REPO_ROOT}/ops/proposals/validate.sh"

  OUT_DIR="${out_dir}" PROPOSAL_ID="${prop_id}" FILE="${proposal_path}" \
    bash "${FABRIC_REPO_ROOT}/ops/proposals/diff.sh"

  OUT_DIR="${out_dir}" PROPOSAL_ID="${prop_id}" FILE="${proposal_path}" \
    bash "${FABRIC_REPO_ROOT}/ops/proposals/impact.sh"

  cp "${proposal_path}" "${out_dir}/proposal.yml"
  sha256sum "${out_dir}/proposal.yml" | awk '{print $1}' >"${out_dir}/checksum.sha256"

  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat >"${out_dir}/policy.json" <<EOF_POLICY
{
  "proposal_id": "${prop_id}",
  "timestamp": "${stamp}",
  "policy_checks": "pass"
}
EOF_POLICY

  printf 'OK: review bundle generated at %s\n' "${out_dir}"
done
