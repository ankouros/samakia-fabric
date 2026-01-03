#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


status="${STATUS:-}"
proposal_id="${PROPOSAL_ID:-}"
approver_id="${APPROVER_ID:-}"
reason="${DECISION_REASON:-}"

if [[ -z "${status}" || -z "${proposal_id}" || -z "${approver_id}" ]]; then
  echo "ERROR: set STATUS, PROPOSAL_ID, APPROVER_ID" >&2
  exit 1
fi

proposal_path=$(find "${FABRIC_REPO_ROOT}/proposals/inbox" -type f -name "proposal.yml" -path "*/${proposal_id}/*" 2>/dev/null | head -n1 || true)
if [[ -z "${proposal_path}" ]]; then
  proposal_path="${FABRIC_REPO_ROOT}/examples/proposals/${proposal_id}.yml"
fi
if [[ ! -f "${proposal_path}" ]]; then
  echo "ERROR: proposal not found for ${proposal_id}" >&2
  exit 1
fi

tenant_id=$(PROPOSAL_PATH="${proposal_path}" python3 - <<'PY'
import os
import yaml
from pathlib import Path
path = Path(os.environ["PROPOSAL_PATH"])
proposal = yaml.safe_load(path.read_text())
print(proposal.get("tenant_id", ""))
PY
)

if [[ -z "${tenant_id}" ]]; then
  echo "ERROR: proposal missing tenant_id" >&2
  exit 1
fi

out_dir="${FABRIC_REPO_ROOT}/evidence/proposals/${tenant_id}/${proposal_id}"
mkdir -p "${out_dir}"

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

PROPOSAL_PATH="${proposal_path}" STATUS="${status}" APPROVER_ID="${approver_id}" DECISION_REASON="${reason}" STAMP="${stamp}" DECISION_OUT="${out_dir}/decision.json" \
  python3 - <<'PY'
import json
import os
from pathlib import Path
import yaml

proposal_path = Path(os.environ["PROPOSAL_PATH"])
status = os.environ["STATUS"]
approver = os.environ["APPROVER_ID"]
reason = os.environ.get("DECISION_REASON")

proposal = yaml.safe_load(proposal_path.read_text())

payload = {
    "proposal_id": proposal.get("proposal_id"),
    "tenant_id": proposal.get("tenant_id"),
    "status": status,
    "approver_id": approver,
    "reason": reason,
    "timestamp": os.environ["STAMP"],
    "environment": proposal.get("scope", {}).get("environment"),
}

Path(os.environ["DECISION_OUT"]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

sha256sum "${out_dir}/decision.json" | awk '{print $1}' >"${out_dir}/decision.sha256"

if [[ "${status}" == "approved" ]]; then
  env_scope=$(PROPOSAL_PATH="${proposal_path}" python3 - <<'PY'
import os
import yaml
from pathlib import Path
proposal = yaml.safe_load(Path(os.environ["PROPOSAL_PATH"]).read_text())
print(proposal.get("scope", {}).get("environment", ""))
PY
)
  if [[ "${env_scope}" == "prod" ]]; then
    if [[ "${EVIDENCE_SIGN:-}" != "1" || -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
      echo "ERROR: prod approval requires EVIDENCE_SIGN=1 and EVIDENCE_SIGN_KEY" >&2
      exit 1
    fi
  fi
fi

if [[ "${EVIDENCE_SIGN:-}" == "1" && -n "${EVIDENCE_SIGN_KEY:-}" ]]; then
  gpg --batch --yes --local-user "${EVIDENCE_SIGN_KEY}" --output "${out_dir}/decision.sha256.asc" --detach-sign "${out_dir}/decision.sha256"
fi

printf 'OK: decision recorded (%s) at %s\n' "${status}" "${out_dir}"
